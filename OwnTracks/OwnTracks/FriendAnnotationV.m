//
//  FriendAnnotationV.m
//  OwnTracks
//
//  Created by Christoph Krey on 15.09.13.
//  Copyright (c) 2013 Christoph Krey. All rights reserved.
//

#import "FriendAnnotationV.h"

@implementation FriendAnnotationV

#define CIRCLE_SIZE 40.0
#define CIRCLE_COLOR [UIColor yellowColor]

#define FENCE_FRIEND_COLOR [UIColor greenColor]
#define FENCE_ME_COLOR [UIColor orangeColor]
#define FENCE_MANUAL_COLOR [UIColor blueColor]
#define FENCE_WIDTH 5.0

#define ID_COLOR [UIColor blackColor]
#define ID_FONTSIZE 20.0
#define ID_INSET 3.0

#define COURSE_COLOR [UIColor blueColor]
#define COURSE_WIDTH 10.0

#define TACHO_COLOR [UIColor redColor]
#define TACHO_SCALE 30.0
#define TACHO_MAX 540.0

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.0];
        self.frame = CGRectMake(0, 0, CIRCLE_SIZE, CIRCLE_SIZE);
    }
    return self;
}

- (void)setPersonImage:(UIImage *)image
{
    if (image) {
        _personImage = [UIImage imageWithCGImage:image.CGImage
                                           scale:(MAX(image.size.width, image.size.height) / CIRCLE_SIZE)
                                     orientation:UIImageOrientationUp];
    } else {
        _personImage = nil;
    }
}

- (UIImage *)getImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(CIRCLE_SIZE, CIRCLE_SIZE), NO, 0.0);
    [self drawRect:CGRectMake(0, 0, CIRCLE_SIZE, CIRCLE_SIZE)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)drawRect:(CGRect)rect
{
    // It is all within a circle
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:rect];
    [circle addClip];

    // Yellow or Photo background
    [CIRCLE_COLOR setFill];
    [circle fill];
    
    // ID
    if (self.personImage != nil) {
        [self.personImage drawInRect:rect];
    }
    
    // Tachometer logarithmic
     
    if (self.speed > 0) {
        UIBezierPath *tacho = [[UIBezierPath alloc] init];
        [tacho moveToPoint:CGPointMake(rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2)];
        [tacho addLineToPoint:CGPointMake(rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height)];
        [tacho appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(rect.size.width / 2, rect.size.height / 2)
                                                         radius:CIRCLE_SIZE / 2
                                                     startAngle:M_PI_2
                                                       endAngle:M_PI_2 +
                           2 * M_PI *log(1 + self.speed / TACHO_SCALE) / log (1 + TACHO_MAX / TACHO_SCALE)
                                                      clockwise:true]];
        [tacho addLineToPoint:CGPointMake(rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2)];
        [tacho closePath];
        
        [TACHO_COLOR setFill];
        [tacho fill];
        [CIRCLE_COLOR setStroke];
        [tacho setLineWidth:1.0];
        [tacho stroke];
    }

    // ID
    if (self.personImage == nil) {
        if ((self.tid != nil && ![self.tid isEqualToString:@""]) || !self.automatic) {
            NSLog(@"TID %@", self.tid);

            UIFont *font = [UIFont boldSystemFontOfSize:ID_FONTSIZE];
            if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending) {
                NSDictionary *attributes = @{NSFontAttributeName: font,
                                             NSForegroundColorAttributeName: ID_COLOR};
                CGRect boundingRect = [self.tid boundingRectWithSize:rect.size options:0 attributes:attributes context:nil];
                CGRect textRect = CGRectMake(rect.origin.x + (rect.size.width - boundingRect.size.width) / 2,
                                             rect.origin.y + (rect.size.height - boundingRect.size.height) / 2,
                                             boundingRect.size.width, boundingRect.size.height);
                
                [self.tid drawInRect:textRect withAttributes:attributes];
            } else {
                CGSize textSize = [self.tid sizeWithFont:font];
                NSLog(@"TextSize %f,%f", textSize.width, textSize.height);
                CGRect textRect = CGRectMake(rect.origin.x + (rect.size.width - textSize.width) / 2,
                                             rect.origin.y + (rect.size.height - textSize.height) / 2,
                                             textSize.width, textSize.height);
                [ID_COLOR set];
                [self.tid drawInRect:textRect withFont:font];
            }
        }
    }
    
    // FENCE
    [circle setLineWidth:FENCE_WIDTH];
    if (self.me) {
        if (self.automatic) {
            [FENCE_ME_COLOR setStroke];
        } else {
            [FENCE_MANUAL_COLOR setStroke];
        }
    } else {
        [FENCE_FRIEND_COLOR setStroke];
    }
    [circle stroke];

    // Course
    UIBezierPath *course = [UIBezierPath bezierPathWithOvalInRect:
                            CGRectMake(
                                       rect.origin.x + rect.size.width / 2 + CIRCLE_SIZE / 2 * cos((self.course -90 )/ 360 * 2 * M_PI) - COURSE_WIDTH / 2,
                                       rect.origin.y + rect.size.height / 2 + CIRCLE_SIZE / 2 * sin((self.course -90 )/ 360 * 2 * M_PI) - COURSE_WIDTH / 2,
                                       COURSE_WIDTH,
                                       COURSE_WIDTH
                                       )
                            ];
    [COURSE_COLOR setFill];
    [course fill];
    [CIRCLE_COLOR setStroke];
    [course setLineWidth:1.0];
    [course stroke];
}


@end
