//
//  ChatViewCell.swift
//  SpeechConverter
//
//  Created by Seema Sharma on 4/1/25.
//

import UIKit

class ChatViewCell: UITableViewCell {
    
    @IBOutlet weak var chatLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.chatLabel.layer.cornerRadius = 5.0
        self.chatLabel.layer.borderWidth = 1.0
        self.chatLabel.layer.borderColor = UIColor.lightGray.cgColor
        self.chatLabel.layer.masksToBounds = true
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
