

#import <Foundation/Foundation.h>

@interface SVGPoint : NSObject {
	float x;
	float y;
}

@property (assign) float x;
@property (assign) float y;

- (id)initWithX:(float)out_x y:(float)out_y;
@end

@protocol SVGQuartzRenderDelegate

	- (void)svgRenderer:(id)renderer
			finishedRenderingInCGContext:(CGContextRef)context;

	- (CGContextRef)svgRenderer:(id)renderer
	requestedCGContextWithSize:(CGSize)size;

@end


@interface SVGQuartzRenderer : NSObject <NSXMLParserDelegate> {
	CGSize documentSize;
	id<SVGQuartzRenderDelegate> delegate;
	CGFloat scaleX;
	CGFloat scaleY;
	CGFloat offsetX;
	CGFloat offsetY;
	CGFloat rotation;
	CGRect viewFrame;
}

@property (readonly) CGSize documentSize;
@property (readonly) id delegate;
@property (readwrite) CGFloat scaleX;
@property (readwrite) CGFloat scaleY;
@property (readwrite) CGFloat offsetX;
@property (readwrite) CGFloat offsetY;
@property (readwrite) CGFloat rotation;
@property (readwrite) CGRect viewFrame;

- (void) resetScale;
- (void)drawSVGFile:(NSString *)file;
- (void)setDelegate:(id<SVGQuartzRenderDelegate>)rendererDelegate;
- (CGContextRef)createBitmapContext;
-(CGPoint) relativeImagePointFrom:(CGPoint)viewPoint;
-(void) locate:(CGPoint)location withBoundingBox:(CGSize)box;

@end
