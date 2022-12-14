//
//  CreateCardTVC.h
//  OwnTracks
//
//  Created by Christoph Krey on 18.07.22.
//  Copyright © 2022 OwnTracks. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CreateCardTVC : UITableViewController <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property (weak, nonatomic) IBOutlet UITextField *name;
@property (weak, nonatomic) IBOutlet UIImageView *cardImage;

@end

NS_ASSUME_NONNULL_END
