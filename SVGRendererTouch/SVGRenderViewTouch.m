
#import "SVGRenderViewTouch.h"
#import <QuartzCore/QuartzCore.h>

@interface SVGRenderViewTouch (private)

- (CGFloat)distanceBetweenTwoPoints:(CGPoint)fromPoint toPoint:(CGPoint)toPoint;

@end

@implementation SVGRenderViewTouch

@synthesize filePath;



- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
		[self setMultipleTouchEnabled:YES];
	
        svgRenderer = [[SVGQuartzRenderer alloc] init];
		[svgRenderer setDelegate:self];
		svgRenderer.viewFrame = frame;
		origin = frame.origin;
		svgRenderer.offsetX = origin.x;
		svgRenderer.offsetY = origin.y;
		initialDistance = -1;
		svgDrawing = NULL;
		initialScaleX = -1;
		initialScaleY = -1;
		panning = NO;
		
		
    }
    return self;
}

-(void) open:(NSString*)path{
	
	self.filePath = path;
	[svgRenderer drawSVGFile:path];
		
}


- (CGContextRef)svgRenderer:(id)renderer
				requestedCGContextWithSize:(CGSize)size
{	
	CGContextRef ctx = [renderer createBitmapContext];
	
	return ctx;
}

- (void)svgRenderer:(id)renderer
		finishedRenderingInCGContext:(CGContextRef)context
{
	NSLog(@"Finished we are!");
	
	
	[svgLayer removeAllAnimations];
	[svgLayer removeFromSuperlayer];
	[svgLayer release];
	
    svgLayer= [[CALayer layer] retain];
    svgLayer.frame = CGRectMake(origin.x,origin.y, svgRenderer.documentSize.width, 
							svgRenderer.documentSize.height);
	[svgLayer setAffineTransform:CGAffineTransformMake(1,0,0,-1,0,0)]; 	
	svgDrawing = CGBitmapContextCreateImage(context);
    svgLayer.contents = (id)svgDrawing;
	CGImageRelease(svgDrawing);
    [self.layer addSublayer:svgLayer];



}


- (CGFloat)distanceBetweenTwoPoints:(CGPoint)fromPoint toPoint:(CGPoint)toPoint {
	
	float x = toPoint.x - fromPoint.x;
    float y = toPoint.y - fromPoint.y;
    
    return sqrt(x * x + y * y);
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *touch = [touches anyObject];
	NSUInteger tapCount = [touch tapCount];
	NSSet* allTouches =  [event allTouches];
	int touchCount = [allTouches count];
	
	switch (touchCount) {
        case 1:
		{
			CGPoint pt = [[[allTouches allObjects] objectAtIndex:0] locationInView:self];
			panning = NO;	
			if (tapCount == 2)
			{
				CGPoint relativeImagePoint = [svgRenderer relativeImagePointFrom:pt];
				if (relativeImagePoint.x <= 1 && relativeImagePoint.y <= 1 && relativeImagePoint.x >= 0 && relativeImagePoint.y >= 0)
				{
					[self locate:relativeImagePoint withBoundingBox:CGSizeMake(0.3,0.3)];
				} else {					
					origin = self.frame.origin;
					svgRenderer.offsetX = self.frame.origin.x;
					svgRenderer.offsetY = self.frame.origin.y;
					[svgRenderer resetScale];
					
					[self open:filePath];
					initialScaleX = -1;
					initialScaleY = -1;

				}				
				
			} else {
				initialPoint =  pt;
				panning = YES;
			}
		}

			break;
			
        default:
        {
			
            // handle multi touch
            UITouch *touch1 = [[allTouches allObjects] objectAtIndex:0];
            UITouch *touch2 = [[allTouches allObjects] objectAtIndex:1];
			
			CGPoint viewPoint1 = [touch1 locationInView:self];
			CGPoint viewPoint2 = [touch2 locationInView:self];
			

			initialDistance = [self distanceBetweenTwoPoints:viewPoint1 toPoint:viewPoint2]; 	
			
			if (initialDistance == 0)
				initialDistance = -1;
			
			initialScaleX = svgRenderer.scaleX;
			initialScaleY = svgRenderer.scaleY;			




            break;
        }
			
    }
	[super touchesBegan:touches withEvent:event];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
	
	NSSet* allTouches =  [event allTouches];
	switch ([allTouches count])
	{
        case 1:
			if (panning)
		    {
				CGPoint newPoint = 	[[[allTouches allObjects] objectAtIndex:0] locationInView:self];
				origin.x += newPoint.x - initialPoint.x;
				origin.y += newPoint.y - initialPoint.y;
				initialPoint = newPoint;
				svgLayer.frame = CGRectMake(origin.x,origin.y, svgRenderer.documentSize.width, 
												svgRenderer.documentSize.height);	
			} 
			
			break;
        default:

			// in a pinch gesture, we scale the image
			if (initialDistance > 0)
			{
				UITouch *touch1 = [[allTouches allObjects] objectAtIndex:0];
				UITouch *touch2 = [[allTouches allObjects] objectAtIndex:1];
				
				CGPoint point1 = [touch1 locationInView:self];
				CGPoint point2 = [touch2 locationInView:self];
				
				CGFloat currentDistance = [self distanceBetweenTwoPoints:point1
																 toPoint:point2];
				
				float oldScale = svgRenderer.scaleX;
				float pinchScale = currentDistance / initialDistance;
				svgRenderer.scaleX = initialScaleX * pinchScale;
				svgRenderer.scaleY = initialScaleY * pinchScale;
				
		
				 
				 //fix point in middle of two touches during zoom 
				 CGPoint middle;
				 middle.x = (point1.x + point2.x)/2;
				 middle.y = (point1.y + point2.y)/2;
				
				 
				float factor = svgRenderer.scaleX/oldScale;
				
				origin.x = (1-factor)*middle.x + factor*origin.x;
				origin.y = (1-factor)*middle.y + factor*origin.y;
				
				
				svgLayer.frame = CGRectMake(origin.x,origin.y, svgRenderer.documentSize.width * pinchScale, 
											svgRenderer.documentSize.height * pinchScale);	
				
				
			}			
           
            break;
	}
				
	
	[super touchesMoved:touches withEvent:event];	
		
   	
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event 
{
	NSSet* allTouches =  [event allTouches];
	switch ([allTouches count])
	{
        case 1:
            panning = NO;
			if (origin.x != self.frame.origin.x || origin.y != self.frame.origin.y)
			{
				
				svgLayer.frame = CGRectMake(self.frame.origin.x,self.frame.origin.y, svgRenderer.documentSize.width, 
											svgRenderer.documentSize.height);
			
				//shift origin in renderer
				svgRenderer.offsetX -= (origin.x - self.frame.origin.x);
				svgRenderer.offsetY -= (origin.y - self.frame.origin.y);
				origin = self.frame.origin;
				
			
				[self open:filePath];	
				
			}
			break;
        default:
			if (initialDistance > 0)
			{
				
				svgLayer.frame = CGRectMake(self.frame.origin.x,self.frame.origin.y, svgRenderer.documentSize.width, 
											svgRenderer.documentSize.height);
				
				
				UITouch *touch1 = [[allTouches allObjects] objectAtIndex:0];
				UITouch *touch2 = [[allTouches allObjects] objectAtIndex:1];
				
				CGPoint point1 = [touch1 locationInView:self];
				CGPoint point2 = [touch2 locationInView:self];
								
				
				//fix point in middle of two touches during zoom 
				CGPoint middle;
				middle.x = (point1.x + point2.x)/2;
				middle.y = (point1.y + point2.y)/2;
				
				// (originBegin + middle)/initialScale = (originEnd + middle)/finalScale
				// originBegin * finalScale + middle * finalScale = originEnd * initialScale + middle * initialScale
				// (originBegin * finalScale + middle * ( finalScale - initialScale))/initialScale = originEnd
								
				
				svgRenderer.offsetX = (svgRenderer.offsetX * svgRenderer.scaleX + middle.x * (svgRenderer.scaleX - initialScaleX))/initialScaleX;
				svgRenderer.offsetY = (svgRenderer.offsetY * svgRenderer.scaleY + middle.y * (svgRenderer.scaleY - initialScaleY))/initialScaleY;
				

				origin = self.frame.origin;
				
				[self open:filePath];									
			}
			initialDistance = -1;			
            break;
	}
	
	[super touchesEnded:touches withEvent:event];


}

//location is (x,y) coordinate of point in unscaled image
-(void) locate:(CGPoint)location withBoundingBox:(CGSize)box
{
	[svgRenderer locate:location withBoundingBox:box];	
}


-(void)dealloc
{
	[svgRenderer release];
	CGImageRelease(svgDrawing);
	[svgLayer release];
	[super dealloc];
}

@end
