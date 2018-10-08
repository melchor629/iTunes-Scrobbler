//
//  AboutViewControler.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 12/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

fileprivate enum LeError: Error {
    case InvalidTranslation(String)
}

class AboutViewController: NSViewController {
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var textLabel: NSTextView!

    private static let translators = [
        ("English", [ ("@melchor629", "http://melchor9000.me") ]),
        ("Español", [ ("@melchor629", "http://melchor9000.me") ]),
        ("Català", [ ("@melchor629", "http://melchor9000.me") ])
    ]

    private static let thanks = [
        ("@Alkesst", "https://alkesst.github.io/#/", "Testing the app"),
        ("@amgxv", "https://github.com/amgxv", "Testing the app")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        let translatorsHtml = AboutViewController.translators.map { "<b>\($0.0)</b>: " + $0.1.map { "<a href=\"\($0.1)\">\($0.0)</a>" }.joined(separator: ", ") + "<br/>" }.joined()
        let thanksHtml = AboutViewController.thanks.map { "<a href=\"\($0.1)\"><b>\($0.0)</b></a>: \($0.2)<br/>" }.joined()
        let aboutHtmlText = NSLocalizedString("ABOUT_HTML_TEXT", comment: "About: About text in HTML format")
            .replacingOccurrences(of: "{TRANSLATORS}", with: translatorsHtml)
            .replacingOccurrences(of: "{THANKS}", with: thanksHtml)
            .replacingOccurrences(of: "{LINK1}", with: "<a href=\"https://github.com/melchor629\">@melchor629</a>")
            .replacingOccurrences(of: "{LINK2}", with: "<a href=\"https://github.com/melchor629/iTunes-Scrobbler/blob/master/LICENSE\">GPL-3.0</a>")
        var showColorCss = false;
        if #available(macOS 10.14, *) {
            showColorCss = NSApp.effectiveAppearance.name == .darkAqua
        }
        let html = """
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    font-family: -apple-system;
                    text-align: center;
                    \(showColorCss ? "color: white;" : "")
                }
            </style>
        </head>
        <body><br/>\(aboutHtmlText)</body>
        """;
        let attributedText = NSAttributedString(html: html.data(using: .utf8)!, options: [:], documentAttributes: nil)
        if let attributedText = attributedText {
            textLabel.textStorage!.setAttributedString(attributedText)
        } else {
            NSApp.presentError(LeError.InvalidTranslation("The translation text is not in HTML format, you cannot view the window :("))
        }
    }
    
    @IBAction func goToWebpage(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "http://melchor9000.me")!)
    }

    @IBAction func goToTheRepo(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/melchor629/iTunes-Scrobbler")!)
    }

}
