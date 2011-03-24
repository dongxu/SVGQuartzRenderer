/*--------------------------------------------------
* Copyright (c) 2010 Joacim Magnusson
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*--------------------------------------------------*/

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
