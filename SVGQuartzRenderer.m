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

#import "SVGQuartzRenderer.h"
#import "NSData+Base64.h"

@implementation SVGPoint
@synthesize x;
@synthesize y;

- (id)initWithX:(float)out_x y:(float)out_y
{
	self = [super init];
	self.x = out_x;
	self.y = out_y;
	return self;
}
@end

@interface SVGQuartzRenderer (hidden)

	- (void)setStyleContext:(NSString *)style;
	- (void)drawPath:(CGMutablePathRef)path withStyle:(NSString *)style;
	- (void)applyTransformations:(NSString *)transformations;
	- (NSDictionary *)getCompleteDefinitionFromID:(NSString *)identifier;
	- (void) cleanupAfterFinishedParsing;

	void CGPathAddRoundRect(CGMutablePathRef path, CGRect rect, float radius);
	void CGPathAddPolygon(CGMutablePathRef path,NSMutableArray *polygonPoints);
	void CGPathAddCircle(CGMutablePathRef path,SVGPoint *center,float r);
	void drawImagePattern(void *fillPatDescriptor, CGContextRef context);
	CGImageRef imageFromBase64(NSString *b64Data);

@end

@implementation SVGQuartzRenderer

@synthesize documentSize;
@synthesize delegate;
@synthesize scale;

struct FillPatternDescriptor {
	CGImageRef imgRef;
	CGRect rect;
}; typedef struct FillPatternDescriptor FillPatternDescriptor;

typedef void (*CGPatternDrawPatternCallback) (void * info,
											  CGContextRef context);

NSXMLParser* xmlParser;
NSString *svgFileName;
CGAffineTransform transform;
CGContextRef cgContext=NULL;
NSMutableDictionary *defDict;
FillPatternDescriptor desc;

NSMutableDictionary *curPat;
NSMutableDictionary *curGradient;
NSMutableDictionary *curFilter;
NSMutableDictionary *curLayer;
NSDictionary *curText;
NSDictionary *curFlowRegion;

BOOL inDefSection = NO;

CGAffineTransform gTransform;
BOOL pathTrnsfrmReset = YES;

// Variables for storing style data
// -------------------------------------------------------------------------
// TODO: This is very messy. Create a class that contains all of these values.
// Then the styling for an element can be represented by a style object.
// Also, the style object could be responsible for parsing CSS and for configuring
// the CGContext according to it's style.
BOOL doFill;
float fillColor[4];
float fillOpacity;
BOOL doStroke = NO;
unsigned int strokeColor = 0;
float strokeWidth = 1.0;
float strokeOpacity;
CGLineJoin lineJoinStyle;
CGLineCap lineCapStyle;
float miterLimit;
CGPatternRef fillPattern;
NSString *fillType;
CGGradientRef fillGradient;
CGPoint fillGradientPoints[2];
int fillGradientAngle;
CGPoint fillGradientCenterPoint;
NSString *font;
float fontSize;
// -------------------------------------------------------------------------

- (id)init {
    self = [super init];
    if (self) {
        xmlParser = [NSXMLParser alloc];
		transform = CGAffineTransformIdentity;

		defDict = [[NSMutableDictionary alloc] init];
		
		scale = 1.0;
    }
    return self;
}

- (void)setDelegate:(id<SVGQuartzRenderDelegate>)rendererDelegate
{
	delegate = rendererDelegate;
}

- (void)resetStyleContext
{
	doFill = YES;
	fillColor[0]=0;
	fillColor[1]=0;
	fillColor[2]=0;
	fillColor[3]=1;
	doStroke = NO;
	strokeColor = 0;
	strokeWidth = 1.0 * scale;
	strokeOpacity = 1.0 * scale;
	lineJoinStyle = kCGLineJoinMiter;
	lineCapStyle = kCGLineCapButt;
	miterLimit = 4;
	fillType = @"solid";
	fillGradientAngle = 0;
	fillGradientCenterPoint = CGPointMake(0, 0);
}

- (void)drawSVGFile:(NSString *)file
{
	svgFileName = [file retain];
	NSData *xml = [NSData dataWithContentsOfFile:file];
	xmlParser = [xmlParser initWithData:xml];
	
	[xmlParser setDelegate:self];
	[xmlParser setShouldResolveExternalEntities:NO];
	[xmlParser parse];
}


// Element began
// -----------------------------------------------------------------------------
- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qualifiedName
	attributes:(NSDictionary *)attrDict
{
	NSAutoreleasePool *pool =  [[NSAutoreleasePool alloc] init];
	
	// Top level SVG node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"svg"]) {
		documentSize = CGSizeMake([[attrDict valueForKey:@"width"] floatValue] * scale,
							   [[attrDict valueForKey:@"height"] floatValue] * scale);
		
		doStroke = NO;
		
		if(delegate) {
		    if (cgContext != nil) 
				CGContextRelease(cgContext);
			cgContext = [delegate svgRenderer:self requestedCGContextWithSize:documentSize];
		}
		gTransform = CGAffineTransformIdentity;
		transform = CGAffineTransformIdentity;
	}
	
	// Definitions
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"defs"]) {
		defDict = [[NSMutableDictionary alloc] init];
		inDefSection = YES;
	}
	
		if([elementName isEqualToString:@"pattern"]) {
			[curPat release];
			curPat = [[NSMutableDictionary alloc] init];
			
			NSEnumerator *enumerator = [attrDict keyEnumerator];
			id key;
			while ((key = [enumerator nextObject])) {
				NSDictionary *obj = [attrDict objectForKey:key];
				[curPat setObject:obj forKey:key];
			}
			NSMutableArray* imagesArray = [NSMutableArray new];
			[curPat setObject:imagesArray forKey:@"images"];
			[imagesArray release];
			[curPat setObject:@"pattern" forKey:@"type"];
		}
			if([elementName isEqualToString:@"image"]) {
				NSMutableDictionary *imageDict = [[NSMutableDictionary alloc] init];
				NSEnumerator *enumerator = [attrDict keyEnumerator];
				id key;
				while ((key = [enumerator nextObject])) {
					NSDictionary *obj = [attrDict objectForKey:key];
					[imageDict setObject:obj forKey:key];
				}
				[[curPat objectForKey:@"images"] addObject:imageDict];
				[imageDict release];
			}
		
		if([elementName isEqualToString:@"linearGradient"]) {
			[curGradient release];
			curGradient = [[NSMutableDictionary alloc] init];
			NSEnumerator *enumerator = [attrDict keyEnumerator];
			id key;
			while ((key = [enumerator nextObject])) {
				NSDictionary *obj = [attrDict objectForKey:key];
				[curGradient setObject:obj forKey:key];
			}
			[curGradient setObject:@"linearGradient" forKey:@"type"];
			NSMutableArray* stopsArray = [NSMutableArray new];
			[curGradient setObject:stopsArray forKey:@"stops"];
			[stopsArray release];
		}
			if([elementName isEqualToString:@"stop"]) {
				NSMutableDictionary *stopDict = [[NSMutableDictionary alloc] init];
				NSEnumerator *enumerator = [attrDict keyEnumerator];
				id key;
				while ((key = [enumerator nextObject])) {
					NSDictionary *obj = [attrDict objectForKey:key];
					[stopDict setObject:obj forKey:key];
				}
				[[curGradient objectForKey:@"stops"] addObject:stopDict];
				[stopDict release];
			}
		
		if([elementName isEqualToString:@"radialGradient"]) {
			[curGradient release];
			curGradient = [[NSMutableDictionary alloc] init];
			NSEnumerator *enumerator = [attrDict keyEnumerator];
			id key;
			while ((key = [enumerator nextObject])) {
				NSDictionary *obj = [attrDict objectForKey:key];
				[curGradient setObject:obj forKey:key];
			}
			[curGradient setObject:@"radialGradient" forKey:@"type"];
		}
	
		if([elementName isEqualToString:@"filter"]) {
			[curFilter release];
			curFilter = [[NSMutableDictionary alloc] init];
			NSEnumerator *enumerator = [attrDict keyEnumerator];
			id key;
			while ((key = [enumerator nextObject])) {
				NSDictionary *obj = [attrDict objectForKey:key];
				[curFilter setObject:obj forKey:key];
			}
			NSMutableArray* gaussianBlursArray = [NSMutableArray new];
			[curFilter setObject:gaussianBlursArray forKey:@"feGaussianBlurs"];
			[gaussianBlursArray release];
		}
			if([elementName isEqualToString:@"feGaussianBlur"]) {
				NSMutableDictionary *blurDict = [[NSMutableDictionary alloc] init];
				NSEnumerator *enumerator = [attrDict keyEnumerator];
				id key;
				while ((key = [enumerator nextObject])) {
					NSDictionary *obj = [attrDict objectForKey:key];
					[blurDict setObject:obj forKey:key];
				}
				[[curFilter objectForKey:@"feGaussianBlurs"] addObject:blurDict];
				[blurDict release];
			}
			if([elementName isEqualToString:@"feColorMatrix"]) {
				
			}
			if([elementName isEqualToString:@"feFlood"]) {
				
			}
			if([elementName isEqualToString:@"feBlend"]) {
				
			}
			if([elementName isEqualToString:@"feComposite"]) {
				
			}
	
	// Group node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"g"]) {
		[curLayer release];
		curLayer = [[NSMutableDictionary alloc] init];
		NSEnumerator *enumerator = [attrDict keyEnumerator];
		id key;
		while ((key = [enumerator nextObject])) {
			NSDictionary *obj = [attrDict objectForKey:key];
			[curLayer setObject:obj forKey:key];
		}
		
		
		// Reset styles for each layer
		[self resetStyleContext];
		
		if([attrDict valueForKey:@"style"])
			[self setStyleContext:[attrDict valueForKey:@"style"]];
		
		if([attrDict valueForKey:@"transform"]) {
			gTransform = CGAffineTransformIdentity;
			[self applyTransformations:[attrDict valueForKey:@"transform"]];
			gTransform = transform;
		}
	}
	
	
	// Path node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"path"]) {
		
		// For now, we'll ignore paths in definitions
		if(inDefSection)
			return;
		
		CGMutablePathRef path = CGPathCreateMutable();
		
		// Create a scanner for parsing path data
		NSString *d = [attrDict valueForKey:@"d"];
		
		// Space before the first command messes stuff up.
		if([d hasPrefix:@" "])
			d = [d stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
		
		NSScanner *scanner = [NSScanner scannerWithString:d];
		[scanner setCaseSensitive:YES];
		[scanner setCharactersToBeSkipped:[NSCharacterSet newlineCharacterSet]];
		
		CGPoint curPoint = CGPointMake(0,0);
		CGPoint curCtrlPoint1 = CGPointMake(-1,-1);
		CGPoint curCtrlPoint2 = CGPointMake(-1,-1);
		CGPoint curArcPoint = CGPointMake(-1,-1);
		CGPoint curArcRadius = CGPointMake(-1,-1);
		CGFloat curArcXRotation = 0.0;
		CGPoint firstPoint = CGPointMake(-1,-1);
		NSString *curCmdType = nil;
		
		NSCharacterSet *cmdCharSet = [NSCharacterSet characterSetWithCharactersInString:@"mMlLhHvVcCsSqQtTaAzZ"];
		NSCharacterSet *separatorSet = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
		NSString *currentCommand = nil;
		NSString *currentParams = nil;
		while ([scanner scanCharactersFromSet:cmdCharSet intoString:&currentCommand]) {
			[scanner scanUpToCharactersFromSet:cmdCharSet intoString:&currentParams];
			
			NSArray *params = [currentParams componentsSeparatedByCharactersInSet:separatorSet];
			
			int paramCount = [params count];
			int mCount = 0;
			
			for (int prm_i = 0; prm_i < paramCount;) {
				if(![[params objectAtIndex:prm_i] isEqualToString:@""]) {
					
					BOOL firstVertex = (firstPoint.x == -1 && firstPoint.y == -1);
					
					// Move to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"M"]) {
						curCmdType = @"line";
						curPoint.x = [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
						mCount++;
					}
					
					// Move to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"m"]) {
						curCmdType = @"line";
						curPoint.x += [[params objectAtIndex:prm_i++] floatValue];
						
						if(firstVertex) {
							curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
						} else {
							curPoint.y += [[params objectAtIndex:prm_i++] floatValue];
						}
						mCount++;
					}
					
					// Line to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"L"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.x = [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Line to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"l"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.x += [[params objectAtIndex:prm_i++] floatValue];
						if(firstVertex) {
							curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
						} else {
							curPoint.y += [[params objectAtIndex:prm_i++] floatValue];
						}
					}
					
					// Horizontal line to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"H"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.x = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Horizontal line to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"h"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.x += [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Vertical line to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"V"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Vertical line to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"v"]) {
						curCmdType = @"line";
						mCount = 2;
						curPoint.y += [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Curve to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"C"]) {
						curCmdType = @"curve";
						
						curCtrlPoint1.x = [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint1.y = [[params objectAtIndex:prm_i++] floatValue];
						
						curCtrlPoint2.x = [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint2.y = [[params objectAtIndex:prm_i++] floatValue];
						
						curPoint.x = [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Curve to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"c"]) {
						curCmdType = @"curve";
						
						curCtrlPoint1.x = curPoint.x + [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint1.y = curPoint.y + [[params objectAtIndex:prm_i++] floatValue];
						
						curCtrlPoint2.x = curPoint.x + [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint2.y = curPoint.y + [[params objectAtIndex:prm_i++] floatValue];
						
						curPoint.x += [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y += [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Shorthand curve to absolute coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"S"]) {
						curCmdType = @"curve";
						
						if(curCtrlPoint2.x != -1 && curCtrlPoint2.y != -1) {
							curCtrlPoint1.x = curCtrlPoint2.x;
							curCtrlPoint1.y = curCtrlPoint2.y;
						} else {
							curCtrlPoint1.x = curPoint.x;
							curCtrlPoint1.y = curPoint.y;
						}
						
						curCtrlPoint2.x = [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint2.y = [[params objectAtIndex:prm_i++] floatValue];
						
						curPoint.x = [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Shorthand curve to relative coord
					//-----------------------------------------
					if([currentCommand isEqualToString:@"s"]) {
						curCmdType = @"curve";
						
						if(curCtrlPoint2.x != -1 && curCtrlPoint2.y != -1) {
							curCtrlPoint1.x = curPoint.x + curCtrlPoint2.x;
							curCtrlPoint1.y = curPoint.y + curCtrlPoint2.x;
						} else {
							curCtrlPoint1.x = curPoint.x;
							curCtrlPoint1.y = curPoint.y;
						}
						
						curCtrlPoint2.x = curPoint.x + [[params objectAtIndex:prm_i++] floatValue];
						curCtrlPoint2.y = curPoint.y + [[params objectAtIndex:prm_i++] floatValue];
						
						curPoint.x += [[params objectAtIndex:prm_i++] floatValue];
						curPoint.y += [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Absolute elliptical arc
					//-----------------------------------------
					if([currentCommand isEqualToString:@"A"]) {
						curArcRadius.x = [[params objectAtIndex:prm_i++] floatValue];
						curArcRadius.y = [[params objectAtIndex:prm_i++] floatValue];
						
						curArcXRotation = [[params objectAtIndex:prm_i++] floatValue];
						
						//Ignore large-arc-flag
						prm_i++;
						
						//Ignore sweep-flag
						prm_i++;
						
						curArcPoint.x = [[params objectAtIndex:prm_i++] floatValue];
						curArcPoint.y = [[params objectAtIndex:prm_i++] floatValue];
					}
					
					// Relative elliptical arc
					//-----------------------------------------
					if([currentCommand isEqualToString:@"a"]) {
						curCmdType = @"arc";
						curArcRadius.x += [[params objectAtIndex:prm_i++] floatValue];
						curArcRadius.y += [[params objectAtIndex:prm_i++] floatValue];
						
						curArcXRotation = [[params objectAtIndex:prm_i++] floatValue];
						
						//Ignore large-arc-flag
						prm_i++;
						
						//Ignore sweep-flag
						prm_i++;
						
						curArcPoint.x += [[params objectAtIndex:prm_i++] floatValue];
						curArcPoint.y += [[params objectAtIndex:prm_i++] floatValue];
					}
					
					
					// Not yet implemented commands
					//-----------------------------------------
					if([currentCommand isEqualToString:@"q"]
					|| [currentCommand isEqualToString:@"Q"]
					|| [currentCommand isEqualToString:@"t"]
					|| [currentCommand isEqualToString:@"T"]) {
						prm_i++;
					}
					
					// Set initial point
					if(firstVertex) {
						firstPoint = curPoint;
						CGPathMoveToPoint(path, NULL, firstPoint.x * scale, firstPoint.y * scale);
					}
					
					// Close path
					if([currentCommand isEqualToString:@"z"] || [currentCommand isEqualToString:@"Z"]) {
						CGPathAddLineToPoint(path, NULL, firstPoint.x * scale, firstPoint.y * scale);
						CGPathCloseSubpath(path);
						curPoint = CGPointMake(-1, -1);
						firstPoint = CGPointMake(-1, -1);
						firstVertex = YES;
						prm_i++;
					}
					
					if(curCmdType) {
						if([curCmdType isEqualToString:@"line"]) {
							if(mCount>1) {
								CGPathAddLineToPoint(path, NULL, curPoint.x * scale, curPoint.y * scale);
							} else {
								CGPathMoveToPoint(path, NULL, curPoint.x * scale, curPoint.y * scale);
							}
						}
						
						if([curCmdType isEqualToString:@"curve"])
							CGPathAddCurveToPoint(path,NULL,curCtrlPoint1.x * scale, curCtrlPoint1.y * scale,
													  curCtrlPoint2.x * scale, curCtrlPoint2.y * scale,
													  curPoint.x * scale,curPoint.y * scale);
						
						if([curCmdType isEqualToString:@"arc"]) {
							CGPathAddArc (path, NULL,
										  curArcPoint.x,
										  curArcPoint.y,
										  curArcRadius.y,
										  curArcXRotation,
										  curArcXRotation,
										  TRUE);							
						}
					}
				} else {
					prm_i++;
				}

			}
			
			currentParams = nil;
		}
		
		
		if([attrDict valueForKey:@"transform"]) {
			[self applyTransformations:[attrDict valueForKey:@"transform"]];
			pathTrnsfrmReset = YES;
		} else if(pathTrnsfrmReset) {
			CGContextConcatCTM(cgContext,CGAffineTransformInvert(transform));
			transform = gTransform;
			CGContextConcatCTM(cgContext,transform);
			pathTrnsfrmReset = NO;
		}
		
		// Respect the 'fill' attribute
		// TODO: This hex parsing stuff is in a bunch of places. It should be cetralized in a function instead.
		if([attrDict valueForKey:@"fill"]) {
			doFill = YES;
			fillType = @"solid";
			NSScanner *hexScanner = [NSScanner scannerWithString:
									 [[attrDict valueForKey:@"fill"] stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
			[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
			unsigned int color;
			[hexScanner scanHexInt:&color];
			fillColor[0] = ((color & 0xFF0000) >> 16) / 255.0f;
			fillColor[1] = ((color & 0x00FF00) >>  8) / 255.0f;
			fillColor[2] =  (color & 0x0000FF) / 255.0f;
			fillColor[3] = 1;
		}
		
		//CGContextClosePath(cgContext);
		[self drawPath:path withStyle:[attrDict valueForKey:@"style"]];
	}
	
	// Parse Circle
	// ------------------------------------------------------------------------
	if ([elementName isEqualToString:@"circle"])
	{
		NSString *cx = [attrDict objectForKey:@"cx"];
		NSString *cy = [attrDict objectForKey:@"cy"];
		SVGPoint *circleCenter = [[SVGPoint alloc] initWithX:[cx floatValue] y:[cy floatValue]];
		float r = [[attrDict objectForKey:@"r"] floatValue];
		
		if([attrDict valueForKey:@"fill"]) {
			doFill = YES;
			fillType = @"solid";
			NSScanner *hexScanner = [NSScanner scannerWithString:
									 [[attrDict valueForKey:@"fill"] stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
			[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
			unsigned int color;
			[hexScanner scanHexInt:&color];
			fillColor[0] = ((color & 0xFF0000) >> 16) / 255.0f;
			fillColor[1] = ((color & 0x00FF00) >>  8) / 255.0f;
			fillColor[2] =  (color & 0x0000FF) / 255.0f;
			fillColor[3] = 1;
		}
		CGMutablePathRef path = CGPathCreateMutable();
		circleCenter.x *= scale;
		circleCenter.y *= scale;
		r *= scale;
		CGPathAddCircle(path,circleCenter,r);
		[self drawPath:path withStyle:[attrDict valueForKey:@"style"]];
		[circleCenter release];
	}
	
	// Parse Polygon
	// ------------------------------------------------------------------------
	if([elementName isEqualToString:@"polygon"])
	{
		//Get Points
		NSMutableArray *pointList = [[NSMutableArray alloc] init];
		if ([attrDict valueForKey:@"points"]) {
			
			NSArray *tempPoints = [[attrDict objectForKey:@"points"] componentsSeparatedByString:@" "];
			for(int i = 0;i < [tempPoints count];i++)
			{
				NSString *tempStr = [tempPoints objectAtIndex:i];
				NSArray *tempPs = [tempStr componentsSeparatedByString:@","];
				if ([tempPs count]>1)
				{
					SVGPoint *point = [[SVGPoint alloc] initWithX:[[tempPs objectAtIndex:0] floatValue] y:[[tempPs objectAtIndex:1] floatValue]];
					point.x *= scale;
					point.y *= scale;
					[pointList addObject:point];
				}
			}
		}
		CGMutablePathRef path = CGPathCreateMutable();
		CGPathAddPolygon(path,pointList);
		//Get fill color
		if([attrDict valueForKey:@"fill"]) {
			doFill = YES;
			fillType = @"solid";
			NSScanner *hexScanner = [NSScanner scannerWithString:
									 [[attrDict valueForKey:@"fill"] stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
			[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
			unsigned int color;
			[hexScanner scanHexInt:&color];
			fillColor[0] = ((color & 0xFF0000) >> 16) / 255.0f;
			fillColor[1] = ((color & 0x00FF00) >>  8) / 255.0f;
			fillColor[2] =  (color & 0x0000FF) / 255.0f;
			fillColor[3] = 1;
		}
		[self drawPath:path withStyle:[attrDict valueForKey:@"style"]];
	}
	
	
	// Rect node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"rect"]) {
		
		// Ignore rects in flow regions for now
		if(curFlowRegion)
			return;
		
		float xPos = [[attrDict valueForKey:@"x"] floatValue];
		float yPos = [[attrDict valueForKey:@"y"] floatValue];
		float width = [[attrDict valueForKey:@"width"] floatValue];
		float height = [[attrDict valueForKey:@"height"] floatValue];
		float ry = [attrDict valueForKey:@"ry"]?[[attrDict valueForKey:@"ry"] floatValue]:-1.0;
		float rx = [attrDict valueForKey:@"rx"]?[[attrDict valueForKey:@"rx"] floatValue]:-1.0;
		
		if (ry==-1.0) ry = rx;
		if (rx==-1.0) rx = ry;
		
		CGMutablePathRef path = CGPathCreateMutable();
		CGPathAddRoundRect(path, CGRectMake(xPos * scale,yPos * scale,width * scale,height * scale), rx * scale);
		
		if([attrDict valueForKey:@"transform"]) {
			[self applyTransformations:[attrDict valueForKey:@"transform"]];
			pathTrnsfrmReset = YES;
		} else if(pathTrnsfrmReset) {
			CGContextConcatCTM(cgContext,CGAffineTransformInvert(transform));
			transform = gTransform;
			CGContextConcatCTM(cgContext,transform);
			pathTrnsfrmReset = NO;
		}
		
		// Respect the 'fill' attribute
		// TODO: This hex parsing stuff is in a bunch of places. It should be cetralized in a function instead.
		if([attrDict valueForKey:@"fill"]) {
			doFill = YES;
			fillType = @"solid";
			NSScanner *hexScanner = [NSScanner scannerWithString:
									 [[attrDict valueForKey:@"fill"] stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
			[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
			unsigned int color;
			[hexScanner scanHexInt:&color];
			fillColor[0] = ((color & 0xFF0000) >> 16) / 255.0f;
			fillColor[1] = ((color & 0x00FF00) >>  8) / 255.0f;
			fillColor[2] =  (color & 0x0000FF) / 255.0f;
			fillColor[3] = 1;
		}
		
		[self drawPath:path withStyle:[attrDict valueForKey:@"style"]];
	}
	
	// Image node
	// Parse the image node only if it contains an xlink:href attribute with base64 data
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"image"]
	&& [[attrDict valueForKey:@"xlink:href"] rangeOfString:@"base64"].location != NSNotFound) {
		
		if(inDefSection)
			return;
		
		float xPos = [[attrDict valueForKey:@"x"] floatValue];
		float yPos = [[attrDict valueForKey:@"y"] floatValue];
		float width = [[attrDict valueForKey:@"width"] floatValue];
		float height = [[attrDict valueForKey:@"height"] floatValue];
		
		pathTrnsfrmReset = YES;
		if([attrDict valueForKey:@"transform"]) {
			[self applyTransformations:[attrDict valueForKey:@"transform"]];
			pathTrnsfrmReset = YES;
		} else if(pathTrnsfrmReset) {
			CGContextConcatCTM(cgContext,CGAffineTransformInvert(transform));
			transform = gTransform;
			CGContextConcatCTM(cgContext,transform);
			pathTrnsfrmReset = NO;
		}
		
		yPos-=height/2;
		CGImageRef theImage = imageFromBase64([attrDict valueForKey:@"xlink:href"]);
		CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, height*scale);
		CGContextConcatCTM(cgContext, flipVertical);
		CGContextDrawImage(cgContext, CGRectMake(xPos*scale, yPos*scale, width*scale, height*scale), theImage);
		CGContextConcatCTM(cgContext, CGAffineTransformInvert(flipVertical));
		CGImageRelease(theImage);
	}
	
	// Text node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"text"]) {
		
		if(inDefSection)
			return;
		
		if(curText)
			[curText release];
		
		// TODO: This chunk of code appears in almost every node. It could probably
		// be centralized
		if([attrDict valueForKey:@"transform"]) {
			[self applyTransformations:[attrDict valueForKey:@"transform"]];
			pathTrnsfrmReset = YES;
		} else if(pathTrnsfrmReset) {
			CGContextConcatCTM(cgContext,CGAffineTransformInvert(transform));
			transform = gTransform;
			CGContextConcatCTM(cgContext,transform);
			pathTrnsfrmReset = NO;
		}
		
		curText = [[NSDictionary dictionaryWithObjectsAndKeys:
				   [attrDict valueForKey:@"id"], @"id",
				   [attrDict valueForKey:@"style"], @"style",
				   [attrDict valueForKey:@"x"], @"x",
				   [attrDict valueForKey:@"y"], @"y",
				   [attrDict valueForKey:@"width"], @"width",
				   [attrDict valueForKey:@"height"], @"height",
				   nil] retain];
		
		[self setStyleContext:[attrDict valueForKey:@"style"]];
	}
	
		// TSpan node
		// Assumed to always be a child of a Text node
		// ---------------------------------------------------------------------
		if([elementName isEqualToString:@"tspan"]) {
			
			if(inDefSection)
				return;
			
			[self setStyleContext:[attrDict valueForKey:@"style"]];
		}
	
	// FlowRegion node
	// -------------------------------------------------------------------------
	if([elementName isEqualToString:@"flowRegion"]) {
		if(curFlowRegion)
			[curFlowRegion release];
		
		curFlowRegion = [[NSDictionary dictionary] retain];
	}
	
	[pool release];
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)chars
{
	// TODO: Text rendering shouldn't occur in this method
	if(curText) {
		
		if(!font)
			font = @"Helvetica";
		
		CGContextSetRGBFillColor(cgContext, fillColor[0], fillColor[1], fillColor[2], fillColor[3]);
		
		CGContextSelectFont(cgContext, [font UTF8String], fontSize*scale, kCGEncodingMacRoman);
		CGContextSetFontSize(cgContext, fontSize*scale);
		CGContextSetTextMatrix(cgContext, CGAffineTransformMakeScale(1.0, -1.0));
		
		// TODO: Messy! Centralize.
		CGFloat red   = ((strokeColor & 0xFF0000) >> 16) / 255.0f;
		CGFloat green = ((strokeColor & 0x00FF00) >>  8) / 255.0f;
		CGFloat blue  =  (strokeColor & 0x0000FF) / 255.0f;
		CGContextSetRGBStrokeColor(cgContext, red, green, blue, strokeOpacity);
		CGContextSetLineWidth(cgContext, strokeWidth);
		CGContextSetLineCap(cgContext, lineCapStyle);
		CGContextSetLineJoin(cgContext, lineJoinStyle);
		CGContextSetMiterLimit(cgContext, miterLimit);
		
		CGTextDrawingMode drawingMode;
		
		if(doFill)
			drawingMode = kCGTextFill;
		
		if(doStroke)
			drawingMode = kCGTextStroke;
		
		if(doStroke && doFill)
			drawingMode = kCGTextFillStroke;
		
		CGContextSetTextDrawingMode(cgContext, drawingMode);
		CGContextShowTextAtPoint(cgContext,
								 [[curText valueForKey:@"x"] floatValue]*scale,
								 [[curText valueForKey:@"y"] floatValue]*scale,
								 [chars UTF8String],
								 [chars length]);
	}
}



// Element ended
// -----------------------------------------------------------------------------
- (void)parser:(NSXMLParser *)parser
 didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
{
	if([elementName isEqualToString:@"svg"]) {
		delegate?[delegate svgRenderer:self didFinnishRenderingFile:svgFileName inCGContext:cgContext]:nil;
		[self cleanupAfterFinishedParsing];
	}
	
	if([elementName isEqualToString:@"g"]) {
	}
	
	if([elementName isEqualToString:@"defs"]) {
		inDefSection = NO;
	}

	if([elementName isEqualToString:@"path"]) {
	}
	
	if([elementName isEqualToString:@"text"]) {
		if(curText) {
			[curText release];
			curText = nil;
		}
	}
	
	if([elementName isEqualToString:@"flowRegion"]) {
		if(curFlowRegion) {
			[curFlowRegion release];
			curFlowRegion = nil;
		}
	}
	
	if([elementName isEqualToString:@"pattern"]) {
		if([curPat objectForKey:@"id"])
		[defDict setObject:curPat forKey:[curPat objectForKey:@"id"]];
	}
	
	if([elementName isEqualToString:@"linearGradient"]) {
		if([curGradient objectForKey:@"id"])
		[defDict setObject:curGradient forKey:[curGradient objectForKey:@"id"]];
	}
	
	if([elementName isEqualToString:@"radialGradient"]) {
		if([curGradient objectForKey:@"id"])
		[defDict setObject:curGradient forKey:[curGradient objectForKey:@"id"]];
	}
}


// Draw a path based on style information
// -----------------------------------------------------------------------------
- (void)drawPath:(CGMutablePathRef)path withStyle:(NSString *)style
{		
	CGContextSaveGState(cgContext);
	
	if(style)
		[self setStyleContext:style];
	
	if(doFill) {
		if ([fillType isEqualToString:@"solid"]) {
			
			//NSLog(@"Setting fill color R:%f, G:%f, B:%f, A:%f", fillColor[0], fillColor[1], fillColor[2], fillColor[3]);
			CGContextSetRGBFillColor(cgContext, fillColor[0], fillColor[1], fillColor[2], fillColor[3]);
			
		} else if([fillType isEqualToString:@"pattern"]) {
			
			CGColorSpaceRef myColorSpace = CGColorSpaceCreatePattern(NULL);
			CGContextSetFillColorSpace(cgContext, myColorSpace);
			CGColorSpaceRelease(myColorSpace);
			
			double alpha = fillColor[3];
			CGContextSetFillPattern (cgContext,
									 fillPattern,
									 &alpha);
			
		} else if([fillType isEqualToString:@"linearGradient"]) {
			
			doFill = NO;
			CGContextAddPath(cgContext, path);
			CGContextSaveGState(cgContext);
			CGContextClip(cgContext);
			CGContextDrawLinearGradient(cgContext, fillGradient, fillGradientPoints[0], fillGradientPoints[1], 3);
			CGContextRestoreGState(cgContext);
			
		} else if([fillType isEqualToString:@"radialGradient"]) {
			
			doFill = NO;
			CGContextAddPath(cgContext, path);
			CGContextSaveGState(cgContext);
			CGContextClip(cgContext);
			CGContextDrawRadialGradient(cgContext, fillGradient, fillGradientCenterPoint, 0, fillGradientCenterPoint, fillGradientPoints[0].y, 3);
			CGContextRestoreGState(cgContext);
			
		}
	}
	
	// Do the drawing
	// -------------------------------------------------------------------------
	if(doStroke) {
		CGFloat red   = ((strokeColor & 0xFF0000) >> 16) / 255.0f;
		CGFloat green = ((strokeColor & 0x00FF00) >>  8) / 255.0f;
		CGFloat blue  =  (strokeColor & 0x0000FF) / 255.0f;
		CGContextSetLineWidth(cgContext, strokeWidth);
		CGContextSetLineCap(cgContext, lineCapStyle);
		CGContextSetLineJoin(cgContext, lineJoinStyle);
		CGContextSetMiterLimit(cgContext, miterLimit);
		CGContextSetRGBStrokeColor(cgContext, red, green, blue, strokeOpacity);
		
	}
	
	if(doFill || doStroke) {
		CGContextAddPath(cgContext, path);
		//NSLog(@"Adding path to contextl");
	}
	
	if(doFill && doStroke) {
		CGContextDrawPath(cgContext, kCGPathFillStroke);
	} else if(doFill) {
		CGContextFillPath(cgContext);
		//NSLog(@"Filling path in contextl");
	} else if(doStroke) {
		CGContextStrokePath(cgContext);
	}
	
	CGContextRestoreGState(cgContext);
	
}

- (void)setStyleContext:(NSString *)style
{
	NSAutoreleasePool *pool =  [[NSAutoreleasePool alloc] init];
	
	// Scan the style string and parse relevant data
	// -------------------------------------------------------------------------
	NSScanner *cssScanner = [NSScanner scannerWithString:style];
	[cssScanner setCaseSensitive:YES];
	[cssScanner setCharactersToBeSkipped:[NSCharacterSet newlineCharacterSet]];
	
	NSString *currentAttribute;
	while ([cssScanner scanUpToString:@";" intoString:&currentAttribute]) {
		NSArray *attrAr = [currentAttribute componentsSeparatedByString:@":"];
		
		NSString *attrName = [attrAr objectAtIndex:0];
		NSString *attrValue = [attrAr objectAtIndex:1];
		
		// --------------------- FILL
		if([attrName isEqualToString:@"fill"]) {
			if(![attrValue isEqualToString:@"none"] && [attrValue rangeOfString:@"url"].location == NSNotFound) {
				
				doFill = YES;
				fillType = @"solid";
				NSScanner *hexScanner = [NSScanner scannerWithString:
										 [attrValue stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
				[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
				unsigned int color;
				[hexScanner scanHexInt:&color];
				fillColor[0] = ((color & 0xFF0000) >> 16) / 255.0f;
				fillColor[1] = ((color & 0x00FF00) >>  8) / 255.0f;
				fillColor[2] =  (color & 0x0000FF) / 255.0f;
				
			} else if([attrValue rangeOfString:@"url"].location != NSNotFound) {
				
				doFill = YES;
				NSScanner *scanner = [NSScanner scannerWithString:attrValue];
				[scanner setCaseSensitive:YES];
				[scanner setCharactersToBeSkipped:[NSCharacterSet newlineCharacterSet]];
				
				NSString *url;
				[scanner scanString:@"url(" intoString:nil];
				[scanner scanUpToString:@")" intoString:&url];
				
				if([url hasPrefix:@"#"]) {
					// Get def by ID
					NSDictionary *def = [self getCompleteDefinitionFromID:url];
					if([def objectForKey:@"images"] && [[def objectForKey:@"images"] count] > 0) {
						
						// Load bitmap pattern
						fillType = [def objectForKey:@"type"];
						NSString *imgString = [[[def objectForKey:@"images"] objectAtIndex:0] objectForKey:@"xlink:href"];
						CGImageRef patternImage = imageFromBase64(imgString);
						
						CGImageRetain(patternImage);
						
						desc.imgRef = patternImage;
						desc.rect = CGRectMake(0, 0, 
											   [[[[def objectForKey:@"images"] objectAtIndex:0] objectForKey:@"width"] floatValue], 
											   [[[[def objectForKey:@"images"] objectAtIndex:0] objectForKey:@"height"] floatValue]);
						CGPatternCallbacks callbacks = { 0, &drawImagePattern, NULL };
						
						fillPattern = CGPatternCreate (
											/* info */		&desc,
											/* bounds */	desc.rect,
											/* matrix */	CGAffineTransformIdentity,
											/* xStep */		desc.rect.size.width,
											/* yStep */		desc.rect.size.height,
											/* tiling */	kCGPatternTilingConstantSpacing,
											/* isColored */	true,
											/* callbacks */	&callbacks);
						
						
					} else if([def objectForKey:@"stops"] && [[def objectForKey:@"stops"] count] > 0) {
						// Load gradient
						fillType = [def objectForKey:@"type"];
						if([def objectForKey:@"x1"]) {
							fillGradientPoints[0] = CGPointMake([[def objectForKey:@"x1"] floatValue] * scale,[[def objectForKey:@"y1"] floatValue] * scale);
							fillGradientPoints[1] = CGPointMake([[def objectForKey:@"x2"] floatValue] * scale,[[def objectForKey:@"y2"] floatValue] * scale);
							//fillGradientAngle = (((atan2(([[def objectForKey:@"x1"] floatValue] - [[def objectForKey:@"x2"] floatValue]),
							//											([[def objectForKey:@"y1"] floatValue] - [[def objectForKey:@"y2"] floatValue])))*180)/M_PI)+90;
						} if([def objectForKey:@"cx"]) {
							fillGradientCenterPoint.x = [[def objectForKey:@"cx"] floatValue] * scale;
							fillGradientCenterPoint.y = [[def objectForKey:@"cy"] floatValue] * scale;
						}
						
						NSArray *stops = [def objectForKey:@"stops"];
						
						CGFloat colors[[stops count]*4];
						CGFloat locations[[stops count]];
						int ci=0;
						for(int i=0;i<[stops count];i++) {
							unsigned int stopColorRGB = 0;
							CGFloat stopColorAlpha = 1;
							
							NSString *style = [[stops objectAtIndex:i] objectForKey:@"style"];
							NSArray *styles = [style componentsSeparatedByString:@";"];
							for(int si=0;si<[styles count];si++) {
								NSArray *valuePair = [[styles objectAtIndex:si] componentsSeparatedByString:@":"];
								if([valuePair count]==2) {
									if([[valuePair objectAtIndex:0] isEqualToString:@"stop-color"]) {
										// Handle color
										NSScanner *hexScanner = [NSScanner scannerWithString:
																 [[valuePair objectAtIndex:1] stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
										[hexScanner scanHexInt:&stopColorRGB];
									}
									if([[valuePair objectAtIndex:0] isEqualToString:@"stop-opacity"]) {
										stopColorAlpha = [[valuePair objectAtIndex:1] floatValue];
									}
								}
							}
							
							CGFloat red   = ((stopColorRGB & 0xFF0000) >> 16) / 255.0f;
							CGFloat green = ((stopColorRGB & 0x00FF00) >>  8) / 255.0f;
							CGFloat blue  =  (stopColorRGB & 0x0000FF) / 255.0f;
							colors[ci++] = red;
							colors[ci++] = green;
							colors[ci++] = blue;
							colors[ci++] = stopColorAlpha;
							
							locations[i] = [[[stops objectAtIndex:i] objectForKey:@"offset"] floatValue];
						}
						
						fillGradient = CGGradientCreateWithColorComponents(CGColorSpaceCreateDeviceRGB(),
																		   colors, 
																		   locations,
																		   [stops count]);
					}
				}
			} else {
				doFill = NO;
			}

		}
		
		// --------------------- FILL-OPACITY
		if([attrName isEqualToString:@"fill-opacity"]) {
			NSScanner *floatScanner = [NSScanner scannerWithString:attrValue];
			[floatScanner scanFloat:&fillColor[3]];
		}
		
		// --------------------- STROKE
		if([attrName isEqualToString:@"stroke"]) {
			if(![attrValue isEqualToString:@"none"]) {
				doStroke = YES;
				NSScanner *hexScanner = [NSScanner scannerWithString:
										 [attrValue stringByReplacingOccurrencesOfString:@"#" withString:@"0x"]];
				[hexScanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; 
				[hexScanner scanHexInt:&strokeColor];
				strokeWidth = 1 * scale;
			} else {
				doStroke = NO;
			}

		}
		
		// --------------------- STROKE-OPACITY
		if([attrName isEqualToString:@"stroke-opacity"]) {
			NSScanner *floatScanner = [NSScanner scannerWithString:attrValue];
			[floatScanner scanFloat:&strokeOpacity];
		}
		
		// --------------------- STROKE-WIDTH
		if([attrName isEqualToString:@"stroke-width"]) {
			NSScanner *floatScanner = [NSScanner scannerWithString:
									   [attrValue stringByReplacingOccurrencesOfString:@"px" withString:@""]];
			[floatScanner scanFloat:&strokeWidth];
			strokeWidth *= scale;
		}
		
		// --------------------- STROKE-LINECAP
		if([attrName isEqualToString:@"stroke-linecap"]) {
			NSScanner *stringScanner = [NSScanner scannerWithString:attrValue];
			NSString *lineCapValue;
			[stringScanner scanUpToString:@";" intoString:&lineCapValue];
			
			if([lineCapValue isEqualToString:@"butt"])
				lineCapStyle = kCGLineCapButt;
			
			if([lineCapValue isEqualToString:@"round"])
				lineCapStyle = kCGLineCapRound;
			
			if([lineCapValue isEqualToString:@"square"])
				lineCapStyle = kCGLineCapSquare;
		}
		
		// --------------------- STROKE-LINEJOIN
		if([attrName isEqualToString:@"stroke-linejoin"]) {
			NSScanner *stringScanner = [NSScanner scannerWithString:attrValue];
			NSString *lineCapValue;
			[stringScanner scanUpToString:@";" intoString:&lineCapValue];
			
			if([lineCapValue isEqualToString:@"miter"])
				lineJoinStyle = kCGLineJoinMiter;
			
			if([lineCapValue isEqualToString:@"round"])
				lineJoinStyle = kCGLineJoinRound;
			
			if([lineCapValue isEqualToString:@"bevel"])
				lineJoinStyle = kCGLineJoinBevel;
		}
		
		// --------------------- STROKE-MITERLIMIT
		if([attrName isEqualToString:@"stroke-miterlimit"]) {
			NSScanner *floatScanner = [NSScanner scannerWithString:attrValue];
			[floatScanner scanFloat:&miterLimit];
		}
		
		// --------------------- FONT-SIZE
		if([attrName isEqualToString:@"font-size"]) {
			NSScanner *floatScanner = [NSScanner scannerWithString:attrValue];
			[floatScanner scanFloat:&fontSize];
		}
		
		// --------------------- FONT-STYLE
		if([attrName isEqualToString:@"font-style"]) {
			
		}
		
		// --------------------- FONT-WEIGHT
		if([attrName isEqualToString:@"font-weight"]) {
			
		}
		
		// --------------------- LINE-HEIGHT
		if([attrName isEqualToString:@"line-height"]) {
			
		}
		
		// --------------------- LETTER-SPACING
		if([attrName isEqualToString:@"letter-spacing"]) {
			
		}
		
		// --------------------- WORD-SPACING
		if([attrName isEqualToString:@"word-spacing"]) {
			
		}
		
		// --------------------- FONT-FAMILY
		if([attrName isEqualToString:@"font-family"]) {
			font = [attrValue retain];
			if([font isEqualToString:@"Sans"])
				font = @"Helvetica";
		}
		
		[cssScanner scanString:@";" intoString:nil];
	}
	[pool release];
}

- (void)applyTransformations:(NSString *)transformations
{
	CGContextConcatCTM(cgContext,CGAffineTransformInvert(transform));
	
	// Reset transformation matrix
	//transform = CGAffineTransformIdentity;
	transform = gTransform;
	
	NSScanner *scanner = [NSScanner scannerWithString:transformations];
	[scanner setCaseSensitive:YES];
	[scanner setCharactersToBeSkipped:[NSCharacterSet newlineCharacterSet]];
	
	NSString *value;
	
	// Translate
	[scanner scanString:@"translate(" intoString:nil];
	[scanner scanUpToString:@")" intoString:&value];
	
	NSArray *values = [value componentsSeparatedByString:@","];
	
	if([values count] == 2)
		transform = CGAffineTransformTranslate (transform,
									[[values objectAtIndex:0] floatValue] * scale,
									[[values objectAtIndex:1] floatValue] * scale);
	
	// Rotate
	value = [NSString string];
	scanner = [NSScanner scannerWithString:transformations];
	[scanner scanString:@"rotate(" intoString:nil];
	[scanner scanUpToString:@")" intoString:&value];
	
	if(value)
		transform = CGAffineTransformRotate(transform, [value floatValue]);
	
	// Matrix
	value = [NSString string];
	scanner = [NSScanner scannerWithString:transformations];
	[scanner scanString:@"matrix(" intoString:nil];
	[scanner scanUpToString:@")" intoString:&value];
	
	values = [value componentsSeparatedByString:@","];
	
	if([values count] == 6) {
		CGAffineTransform matrixTransform = CGAffineTransformMake ([[values objectAtIndex:0] floatValue],
																   [[values objectAtIndex:1] floatValue],
																   [[values objectAtIndex:2] floatValue],
																   [[values objectAtIndex:3] floatValue],
																   [[values objectAtIndex:4] floatValue],
																   [[values objectAtIndex:5] floatValue]);
		transform = CGAffineTransformConcat(transform, matrixTransform);
	}
	
	// Apply to graphics context
	//CGContextConcatCTM(cgContext,gTransform);
	CGContextConcatCTM(cgContext,transform);
}

- (NSDictionary *)getCompleteDefinitionFromID:(NSString *)identifier
{
	NSString *theId = [identifier stringByReplacingOccurrencesOfString:@"#" withString:@""];
	NSMutableDictionary *def = [defDict objectForKey:theId];
	NSString *xlink = [def objectForKey:@"xlink:href"];
	while(xlink){
		NSMutableDictionary *linkedDef = [defDict objectForKey:
										  [xlink stringByReplacingOccurrencesOfString:@"#" withString:@""]];
		
		if([linkedDef objectForKey:@"images"])
			[def setObject:[linkedDef objectForKey:@"images"] forKey:@"images"];
		
		if([linkedDef objectForKey:@"stops"])
			[def setObject:[linkedDef objectForKey:@"stops"] forKey:@"stops"];
		
		xlink = [linkedDef objectForKey:@"xlink:href"];
	}
	
	return def;
}

- (CGContextRef)createBitmapContext
{
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, (int)documentSize.width, (int)documentSize.height, 8, (int)documentSize.width*4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
	return ctx;
}

void drawImagePattern(void * fillPatDescriptor, CGContextRef context)
{
	FillPatternDescriptor *patDesc;
	patDesc = (FillPatternDescriptor *)fillPatDescriptor;
	CGContextDrawImage(context, patDesc->rect, patDesc->imgRef);
	CGImageRelease(patDesc->imgRef);
}

CGImageRef imageFromBase64(NSString *b64Data)
{
	NSArray *mimeAndData = [b64Data componentsSeparatedByString:@","];
	NSData *imgData = [NSData dataWithBase64EncodedString:[mimeAndData objectAtIndex:1]];
	CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)imgData);
	
	CGImageRef img=nil;
	if([[mimeAndData objectAtIndex:0] isEqualToString:@"data:image/jpeg;base64"])
		img = CGImageCreateWithJPEGDataProvider(provider, NULL, true, kCGRenderingIntentDefault);
	else if([[mimeAndData objectAtIndex:0] isEqualToString:@"data:image/png;base64"])
		img = CGImageCreateWithPNGDataProvider(provider, NULL, true, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	return img;
}

void CGPathAddCircle(CGMutablePathRef path,SVGPoint *center,float r)
{
	CGRect bounds = CGRectMake(center.x - r, center.y - r, 2*r , 2*r);
	CGPathAddEllipseInRect(path, NULL, bounds);
}

void CGPathAddPolygon(CGMutablePathRef path,NSMutableArray *polygonPoints)
{
	for(int i = 0;i < [polygonPoints count];i++)
	{
		SVGPoint *point = [polygonPoints objectAtIndex:i];
		//Draw the point
		if (i == 0)
		{
			CGPathMoveToPoint(path,NULL, point.x, point.y);
		}
		else {
			CGPathAddLineToPoint(path,NULL, point.x, point.y);
		}
	}
}

void CGPathAddRoundRect(CGMutablePathRef path, CGRect rect, float radius)
{
	CGPathMoveToPoint(path, NULL, rect.origin.x, rect.origin.y + radius);
	
	CGPathAddLineToPoint(path, NULL, rect.origin.x, rect.origin.y + rect.size.height - radius);
	CGPathAddArc(path, NULL, rect.origin.x + radius, rect.origin.y + rect.size.height - radius, 
					radius, M_PI / 1, M_PI / 2, 1);
	
	CGPathAddLineToPoint(path, NULL, rect.origin.x + rect.size.width - radius, 
							rect.origin.y + rect.size.height);
	CGPathAddArc(path, NULL, rect.origin.x + rect.size.width - radius, 
					rect.origin.y + rect.size.height - radius, radius, M_PI / 2, 0.0f, 1);
	
	CGPathAddLineToPoint(path, NULL, rect.origin.x + rect.size.width, rect.origin.y + radius);
	CGPathAddArc(path, NULL, rect.origin.x + rect.size.width - radius, rect.origin.y + radius, 
					radius, 0.0f, -M_PI / 2, 1);
	
	CGPathAddLineToPoint(path, NULL, rect.origin.x + radius, rect.origin.y);
	CGPathAddArc(path, NULL, rect.origin.x + radius, rect.origin.y + radius, radius, 
					-M_PI / 2, M_PI, 1);
}

- (void)dealloc
{
	[self cleanupAfterFinishedParsing];
	[xmlParser release];
	
	[super dealloc];
}

-(void) cleanupAfterFinishedParsing
{
	[defDict release];
	defDict = nil;
	[curPat release];
	curPat = nil;
	[curGradient release];
	curGradient = nil;
	[curFilter release];
	curFilter = nil;
	[curText release];
	curText = nil;
	[font release];
	font = nil;
	if(cgContext)
		CGContextRelease(cgContext);
	cgContext = nil;
	
}

@end
