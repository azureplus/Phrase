//
//  InitialViewController.swift
//  Phrase
//
//  Created by subli on 5/28/20.
//  Copyright © 2020 subli. All rights reserved.
//

import Foundation
import UIKit
import Zip

class InitialViewController: UIViewController {
	
	@IBOutlet weak var tableView: UITableView!
	
	let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
	let downloadService = DownloadService()
	var downloadableItem: [DownloadableItem] = []
	let lineMaxWidth: Int32 = 200
	var destinationUrl: URL? = nil
	var progress: Float = 0
	
	let enFileName = "OpenSubtitles.en-es.en"
	let esFileName = "OpenSubtitles.en-es.es"
	var datasetFileName: String? = nil
	var timer = Timer()
	
	lazy var downloadsSession: URLSession = {
		let configuration = URLSessionConfiguration.background(withIdentifier:
			"com.williamstahlberg.Phrase.urlSession")
		return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
	}()
	
	@objc func updateCombineProgress() {
		var a: Double = 0
		C_combine_get_globals(&a)
		progress = Float(a)
		let status = "Joining files..."
		
		if let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? TableCell {
			cell.updateDisplay(progress: progress, status: status)
		}
	}
	
	func processDownload(url: URL) {
		guard let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? TableCell else {
			return
		}
		cell.progressLabel.textAlignment = .center
		cell.progressLabel.text = "Unzipping..."
		
		var unzipDirectory: URL? = nil
		do {
			unzipDirectory = try Zip.quickUnzipFile(url)
		} catch {
			print("Something went wrong while unzipping.")
		}
		
		if let unzipDirectory = unzipDirectory, let datasetFileName = datasetFileName {
			let urlEn = unzipDirectory.appendingPathComponent(enFileName)
			let urlEs = unzipDirectory.appendingPathComponent(esFileName)
			let urlDestination = unzipDirectory.appendingPathComponent(datasetFileName)
			cell.progressLabel.text = "Joining files..."
			
			print("\ndatasetFileName:")
			print(datasetFileName)
			
			DispatchQueue.global(qos: .userInitiated).async {
				
				C_combine(urlEn.path, urlEs.path, urlDestination.path, self.lineMaxWidth)
				DispatchQueue.main.async {
					self.timer.invalidate()
//					self.cleanUpDirectory(directory: url.deletingLastPathComponent(), keep: [urlDestination])
					self.dismiss(animated: true, completion: nil)
				}
			}
			
			timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateCombineProgress), userInfo: nil, repeats: true)

		}
	}
	
	func cleanUpDirectory(directory: URL, keep urlsToKeep: [URL]) {
		let fileManager = FileManager.default
		var newUrlsToKeep: [URL] = []
		
		do {
			for url in urlsToKeep {
				let name = url.lastPathComponent
				let destination = documentDirectory.appendingPathComponent(name)
				try fileManager.moveItem(at: url, to: destination)
				newUrlsToKeep.append(destination)
			}
		} catch let error {
			print("Could not copy file to disk: \(error.localizedDescription)")
		}
		
		do {
			let resourceKeys : [URLResourceKey] = [.creationDateKey, .isDirectoryKey]
			let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
			let enumerator = FileManager.default.enumerator(at: documentsURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles], errorHandler: { (url, error) -> Bool in
				return true
			})!
			
			for case let url as URL in enumerator {
				if !newUrlsToKeep.contains(url) {
					try? fileManager.removeItem(at: url)
				}
			}
		} catch {
			print(error)
		}
	}
	
	func reload(_ row: Int) {
		tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		self.isModalInPresentation = true
		
		tableView.tableFooterView = UIView()
		downloadService.downloadsSession = downloadsSession

		let url = URL(string: "http://192.168.1.115/small/en-es.txt.zip")!
//		let url = URL(string: "http://192.168.0.21/small/en-es.txt.zip")!
//		let url = URL(string: "http://192.168.0.15/en-es.txt.zip")!
//		let url = URL(string: "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/moses/en-es.txt.zip")!
		downloadableItem.append(DownloadableItem(
			title: "OpenSubtitles2018 en-es",
			subTitle: url.absoluteString,
			url: url,
			index: 0
		))
		
		print("datasetFileName:\(datasetFileName!)")
	}
	
//	override func viewDidAppear(_ animated: Bool) {
//		self.dismiss(animated: true, completion: nil)
//	}
	
}

extension InitialViewController: UITableViewDataSource {
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell: TableCell = tableView.dequeueReusableCell(withIdentifier: TableCell.identifier, for: indexPath) as! TableCell
		
		// Delegate cell button tap events to this view controller.
		cell.delegate = self
		
		let track = downloadableItem[indexPath.row]
		cell.configure(
			track: track,
			downloaded: track.downloaded,
			download: downloadService.activeDownloads[track.url],
			processing: timer.isValid
		)

		return cell
	}
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return downloadableItem.count
	}
}

extension InitialViewController: TableCellDelegate {
	func cancelTapped(_ cell: TableCell) {
		if let indexPath = tableView.indexPath(for: cell) {
			let track = downloadableItem[indexPath.row]
			downloadService.cancelDownload(track)
			reload(indexPath.row)
		}
	}
	
	func downloadTapped(_ cell: TableCell) {
		if let indexPath = tableView.indexPath(for: cell) {
			let track = downloadableItem[indexPath.row]
			downloadService.startDownload(track)
			reload(indexPath.row)
		}
	}
	
	func pauseTapped(_ cell: TableCell) {
		if let indexPath = tableView.indexPath(for: cell) {
			let track = downloadableItem[indexPath.row]
			downloadService.pauseDownload(track)
			if let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? TableCell {
				cell.pauseOrResumeButton.setTitle("Resume", for: .normal)
			}
//			reload(indexPath.row)
		}
	}
	
	func resumeTapped(_ cell: TableCell) {
		if let indexPath = tableView.indexPath(for: cell) {
			let track = downloadableItem[indexPath.row]
			downloadService.resumeDownload(track)
			reload(indexPath.row)
		}
	}
}

extension InitialViewController: URLSessionDelegate {
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		DispatchQueue.main.async {
			if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
				let completionHandler = appDelegate.backgroundSessionCompletionHandler {
				appDelegate.backgroundSessionCompletionHandler = nil
				completionHandler()
			}
		}
	}
}

extension InitialViewController: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let sourceURL = downloadTask.originalRequest?.url else {
			return
		}
		
		let download = downloadService.activeDownloads[sourceURL]
		downloadService.activeDownloads[sourceURL] = nil
		
		let documentsURL = try? FileManager.default.url(
			for: .documentDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: false)
		self.destinationUrl = documentsURL!.appendingPathComponent(sourceURL.lastPathComponent)
		
		let fileManager = FileManager.default
		try? fileManager.removeItem(at: self.destinationUrl!)
		
		do {
			try fileManager.copyItem(at: location, to: self.destinationUrl!)
			download?.track.downloaded = true
		} catch let error {
			print("Could not copy file to disk: \(error.localizedDescription)")
		}
		
		DispatchQueue.main.async {
			self.processDownload(url: self.destinationUrl!)
		}
		
		if let index = download?.track.index {
			DispatchQueue.main.async { [weak self] in
				self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
			}
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard
			let url = downloadTask.originalRequest?.url,
			let download = downloadService.activeDownloads[url]	else {
				return
		}
		
		download.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
		let totalSize = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
		let status = String(format: "%.1f%% of %@", download.progress * 100, totalSize)
		
		DispatchQueue.main.async {
			if let cell = self.tableView.cellForRow(at: IndexPath(row: download.track.index, section: 0)) as? TableCell {
				cell.updateDisplay(progress: download.progress, status: status)
			}
		}
	}
}
