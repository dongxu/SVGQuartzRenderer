
#import "SVGRenderView.h"

@implementation SVGRenderView

CGImageRef svgDrawing=NULL;
BOOL hasRendered;

SVGQuartzRenderer *svgRenderer;
CGContextRef viewContext;
NSString *svgFile;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        svgRenderer = [[SVGQuartzRenderer alloc] init];
		[svgRenderer setDelegate:self];
		[svgRenderer setScale:1.0];
    }
    return self;
}

- (IBAction)openFile:(id)sender
{	
	NSOpenPanel *chooseDirPanel = [NSOpenPanel openPanel];
	[chooseDirPanel setTitle:@"Open SVG file"];
	[chooseDirPanel setPrompt:@"Open"];
	[chooseDirPanel setAllowedFileTypes:[NSArray arrayWithObject:@"SVG"]];
	[chooseDirPanel setCanChooseDirectories:NO];
	[chooseDirPanel setCanCreateDirectories:YES];
	
	int selected = [chooseDirPanel runModal];
	
	if(selected == NSOKButton) {
		
		if(svgFile)
			[svgFile release];
		
		svgFile = [chooseDirPanel filename];
		[svgRenderer drawSVGFile:svgFile];
		
	} else if(selected == NSCancelButton) {
		// Cancel
		return;
	} else {
		return;
	}
}

- (void)awakeFromNib
{
}

- (void)drawRect:(NSRect)dirtyRect {
	
	viewContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	CGContextDrawImage(viewContext, CGRectMake([self frame].origin.x, 
											   [self frame].origin.y, 
											   [self frame].size.width, 
											   [self frame].size.height), svgDrawing);

}

- (CGContextRef)svgRenderer:(id)renderer
				requestedCGContextWithSize:(CGSize)size
{
	[self setFrame:NSMakeRect(0, 0, size.width, size.height)];
	
	CGContextRef ctx = [renderer createBitmapContext];
	
	return ctx;
}

- (void)svgRenderer:(id)renderer
		didFinnishRenderingFile:(NSString *)file
		inCGContext:(CGContextRef)context
{

	CGImageRelease(svgDrawing);	
	svgDrawing = CGBitmapContextCreateImage(context);
}

- (IBAction)setScale:(id)sender
{
	if(sender == scaleTF)
		[scaleSlider setFloatValue:[sender floatValue]];
	else 
		[scaleTF setFloatValue:[sender floatValue]];
	
	[svgRenderer setScale:[sender floatValue]];
	[svgRenderer drawSVGFile:svgFile];
}

- (BOOL)isFlipped {return YES;}

-(void)dealloc
{
	CGImageRelease(svgDrawing);
	[svgRenderer release];
	[super dealloc];
}

@end
