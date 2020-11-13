//
//  FormatTableViewController.swift
//  YD
//
//  Created by 안창범 on 2020/08/31.
//  Copyright © 2020 Kewlbear. All rights reserved.
//

import UIKit
import YoutubeDL

class FormatTableViewController: UITableViewController {

    var formats: [Format] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return formats.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        cell.textLabel?.text = formats[indexPath.row].description

        return cell
    }

    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let format = formats[indexPath.row]
        guard let request = format.urlRequest else {
            assertionFailure()
            return
        }
        let video = format.format["vcodec"] != "none"
        let audio = format.format["acodec"] != "none"
        let task = Downloader.shared.download(request: request, kind: video ? (audio ? .complete : .videoOnly) : .audioOnly)
        
        let download = navigationController?.viewControllers.dropLast().last as? DownloadViewController
        download?.progressView.observedProgress = task.progress
    }
}
