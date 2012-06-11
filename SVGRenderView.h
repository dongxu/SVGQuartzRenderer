
#import <Cocoa/Cocoa.h>
#import "SVGQuartzRenderer.h"

@interface SVGRenderView : NSView <SVGQuartzRenderDelegate> {
	IBOutlet NSSlider *scaleSlider;
	IBOutlet NSTextField *scaleTF;
}

- (IBAction)openFile:(id)sender;
- (IBAction)setScale:(id)sender;

@end
