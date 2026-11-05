#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface BuildBoxRunnerHook : NSObject
@end

static NSString *getTargetOrg() {
    NSString *org = [[NSUserDefaults standardUserDefaults] stringForKey:@"bb_github_org"];
    if (!org || org.length == 0) {
        return @"jojirokuNet";
    }
    return org;
}

static NSString *getRunnerLabels() {
    NSString *labels = [[NSUserDefaults standardUserDefaults] stringForKey:@"bb_runner_labels"];
    if (!labels || labels.length == 0) {
        return @"[self-hosted, macOS, ARM64]";
    }
    return labels;
}

static NSURLRequest *modifyGitHubRequest(NSURLRequest *request) {
    if (!request || !request.URL) return request;
    
    NSString *urlStr = request.URL.absoluteString;
    NSMutableURLRequest *req = [request mutableCopy];
    BOOL modified = NO;
    
    // 1. Redirect repository creation to target organization
    if ([urlStr containsString:@"api.github.com/user/repos"] && [request.HTTPMethod isEqualToString:@"POST"]) {
        NSString *org = getTargetOrg();
        NSString *newUrlStr = [NSString stringWithFormat:@"https://api.github.com/orgs/%@/repos", org];
        req.URL = [NSURL URLWithString:newUrlStr];
        NSLog(@"[BuildBoxRunnerHook] Redirected repo creation -> %@", newUrlStr);
        modified = YES;
    }
    
    // 2. Intercept pushing workflow file to inject self-hosted runner and workspace cleanup
    if (request.HTTPBody) {
        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:NSJSONReadingMutableContainers error:&err];
        if (json && [json isKindOfClass:[NSDictionary class]] && json[@"content"]) {
            NSString *b64Content = json[@"content"];
            NSString *cleanB64 = [b64Content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
            cleanB64 = [cleanB64 stringByReplacingOccurrencesOfString:@"\r" withString:@""];
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:cleanB64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if (decodedData) {
                NSString *fileText = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                if (fileText && [fileText containsString:@"name: Build IPA"] && [fileText containsString:@"runs-on:"]) {
                    NSLog(@"[BuildBoxRunnerHook] Intercepting build-ipa.yml to target self-hosted runner!");
                    
                    NSString *targetRunner = [NSString stringWithFormat:@"runs-on: %@", getRunnerLabels()];
                    NSString *updated = [fileText stringByReplacingOccurrencesOfString:@"runs-on: macos-latest" withString:targetRunner];
                    
                    // Inject clean workspace step if not present
                    if (![updated containsString:@"Clean workspace"]) {
                        NSString *needle = @"- uses: actions/checkout@v4\n";
                        NSString *replacement = @"- uses: actions/checkout@v4\n        with:\n          clean: true\n      \n      - name: Clean workspace\n        run: |\n          rm -rf BuildApp BuildAppBinary *.app Payload *.ipa 2>/dev/null || true\n";
                        if ([updated containsString:needle]) {
                            updated = [updated stringByReplacingOccurrencesOfString:needle withString:replacement];
                        }
                    }
                    
                    NSData *newEncodedData = [updated dataUsingEncoding:NSUTF8StringEncoding];
                    NSString *newB64 = [newEncodedData base64EncodedStringWithOptions:0];
                    NSMutableDictionary *mutJson = [json mutableCopy];
                    mutJson[@"content"] = newB64;
                    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:mutJson options:0 error:nil];
                    modified = YES;
                    NSLog(@"[BuildBoxRunnerHook] Successfully patched workflow YAML to self-hosted runner!");
                }
            }
        }
    }
    
    return modified ? req : request;
}

@implementation BuildBoxRunnerHook

+ (void)load {
    NSLog(@"[BuildBoxRunnerHook] Loaded into BuildBox 2.1.4!");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class sessionClass = [NSURLSession class];
        
        SEL origDataSel = @selector(dataTaskWithRequest:completionHandler:);
        Method origDataMethod = class_getInstanceMethod(sessionClass, origDataSel);
        if (origDataMethod) {
            NSURLSessionDataTask *(*origImp)(id, SEL, NSURLRequest *, id) = (void *)method_getImplementation(origDataMethod);
            id newImpBlock = ^NSURLSessionDataTask *(id self, NSURLRequest *request, id completionHandler) {
                NSURLRequest *modReq = modifyGitHubRequest(request);
                return origImp(self, origDataSel, modReq, completionHandler);
            };
            method_setImplementation(origDataMethod, imp_implementationWithBlock(newImpBlock));
            NSLog(@"[BuildBoxRunnerHook] Successfully swizzled dataTaskWithRequest:completionHandler:");
        }
    });
}

@end
