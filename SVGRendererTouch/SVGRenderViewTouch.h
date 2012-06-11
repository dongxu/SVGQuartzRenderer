
#import <UIKit/UIKit.h>
#import "SVGQuartzRenderer.h"

@interface SVGRenderViewTouch : UIView <SVGQuartzRenderDelegate> {
	CGPoint origin;
	CGImageRef svgDrawing;
	CGFloat initialDistance;
	CGPoint initialPoint;
	CGFloat initialScaleX;
	CGFloat initialScaleY;
	BOOL panning;
	SVGQuartzRenderer *svgRenderer;
	CGContextRef viewContext;
	NSString* filePath;
	
	CALayer* svgLayer;
}

-(void) open:(NSString*)path;
-(void) locate:(CGPoint)location withBoundingBox:(CGSize)box;

@property (nonatomic, copy) NSString* filePath;

@end
