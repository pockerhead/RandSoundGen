//
//  ViewController.swift
//  RandSoundGen
//
//  Created by Артём Балашов on 13.05.2024.
//

import UIKit
import AVFoundation
import Combine

class ViewController: UIViewController {

	let gen = RandSoundGen()
	var cancellable: AnyCancellable?
	
	let meterView = UIProgressView(progressViewStyle: .default)
	
	lazy var button = UIButton(type: .system, primaryAction: .init(
		title: "GET SOME FUN",
		handler: { _ in
			Task {
				let n = try await self.gen.getSomeRandomNumbers()
				let nNormalized = n.map({
					abs($0 * 1_000_000_000).truncatingRemainder(dividingBy: 1_00)
				})
				print(n)
				print(nNormalized)
			}
		})
	)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		view.addSubview(button)
		cancellable = gen.meterPublisher.sink {[self] level in
			let normalized = (level + 80) / 90
			meterView.setProgress(Float(normalized), animated: false)
		}
		view.addSubview(meterView)
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		button.sizeToFit()
		button.center = view.center
		meterView.frame = .init(x: 0, y: button.frame.maxY + 16, width: view.frame.width, height: 32)
	}


}

final class RandSoundGen: NSObject, AVAudioRecorderDelegate {
	var recordingSession: AVAudioSession?
	var audioRecorder: AVAudioRecorder?
	
	var meterPublisher: PassthroughSubject<Double, Never> = .init()
	
	let timer = Timer.publish(every: 0.005, on: .main, in: .common)
	var cancellable: AnyCancellable?
	@MainActor var numbers: [Double] = []
	
	override init() {
		super.init()
	}
	
	func getSomeRandomNumbers() async throws -> [Double] {
		recordingSession = AVAudioSession.sharedInstance()
		try recordingSession?.setCategory(.playAndRecord, mode: .default)
		try recordingSession?.setActive(true)
		if await AVAudioApplication.requestRecordPermission() {
			return try await getFile()
		} else {
			fatalError()
		}
	}
	
	func assignTimer() {
		cancellable = timer.autoconnect().sink(receiveValue: {[weak self] _ in
			guard let self = self else { return }
			audioRecorder?.updateMeters()
			
			guard
				let averageLevel = audioRecorder?.averagePower(forChannel: 0),
				let peakLevel = audioRecorder?.peakPower(forChannel: 0)
			else { return }
//			print(averageLevel, peakLevel)
			self.meterPublisher.send(Double(averageLevel))
			Task {
				await MainActor.run {
					self.numbers.append(Double(averageLevel))
				}
			}
		})
	}
	
	func getDocumentsDirectory() -> URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		return paths[0]
	}
	
	func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
		if !flag {
			finishRecording(success: false)
		}
	}
	
	func finishRecording(success: Bool) {
		audioRecorder?.stop()
		audioRecorder = nil
		cancellable = nil
	}
	
	func getFile() async throws -> [Double] {
		let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")

		let settings = [
			AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
			AVSampleRateKey: 44100,
			AVNumberOfChannelsKey: 1,
			AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
		]
		await MainActor.run {
			numbers = []
		}
		do {
			audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
			audioRecorder?.delegate = self
			audioRecorder?.prepareToRecord()
			audioRecorder?.isMeteringEnabled = true
			audioRecorder?.record()
			assignTimer()
			try await Task.sleep(for: .seconds(0.026))
			finishRecording(success: true)
			return await numbers
		} catch {
			finishRecording(success: false)
			throw error
		}
	}
}
