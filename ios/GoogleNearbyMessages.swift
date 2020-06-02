//
//  GoogleNearbyMessages.swift
//  GoogleNearbyMessages
//
//  Created by Marc Rousavy on 02.06.20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation

@objc(NearbyMessages)
class NearbyMessages: RCTEventEmitter {
	enum EventType: String {
		case MESSAGE_FOUND
		case MESSAGE_LOST
		case BLUETOOTH_ERROR
		case PERMISSION_ERROR
	}
	enum GoogleNearbyMessagesError: Error, LocalizedError {
		case permissionError(permissionName: String)
		case runtimeError(message: String)
		
		public var errorDescription: String? {
			switch self {
			case .permissionError(permissionName: let permissionName):
				return "Permission has been denied! Denied Permission: \(permissionName). Make sure to include NSBluetoothPeripheralUsageDescription in your Info.plist!"
			case .runtimeError(message: let message):
				return message
			}
		}
	}

	
	private var messageManager: GNSMessageManager? = nil
	private var currentPublication: GNSPublication? = nil
	private var currentSubscription: GNSSubscription? = nil
	
	@objc(constantsToExport)
	override public func constantsToExport() -> [AnyHashable : Any]! {
	  return ["initialCount": 0]
	}
	
	@objc(connect:resolver:rejecter:)
	func connect(_ apiKey: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		do {
			// TODO: remove debug logging
			GNSMessageManager.setDebugLoggingEnabled(true)
			
			let hasPermission = GNSPermission.isGranted()
			if (!hasPermission) {
				throw GoogleNearbyMessagesError.permissionError(permissionName: "Bluetooth/Microphone")
			}
			
			self.messageManager = GNSMessageManager(apiKey: apiKey,
													paramsBlock: { (params: GNSMessageManagerParams?) in
														guard let params = params else { return }
														params.microphonePermissionErrorHandler = { (hasError: Bool) in
															self.sendEvent(withName: EventType.PERMISSION_ERROR.rawValue, body: [ "permission": "microphone" ]);
														}
														params.bluetoothPowerErrorHandler = { (hasError: Bool) in
															self.sendEvent(withName: EventType.BLUETOOTH_ERROR.rawValue, body: [ "hasError": hasError ]);
														}
														params.bluetoothPermissionErrorHandler = { (hasError: Bool) in
															self.sendEvent(withName: EventType.PERMISSION_ERROR.rawValue, body: [ "message": "bluetooth" ]);
														}
														// TODO: Strategy to use BLE only
			})
			resolve(nil)
		} catch {
			reject("GOOGLE_NEARBY_MESSAGES_ERROR_CONNECT", error.localizedDescription, error)
		}
	}
	
	@objc(disconnect:rejecter:)
	func disconnect(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		self.currentSubscription = nil
		self.currentPublication = nil
		self.messageManager = nil
		resolve(nil)
	}
	
	@objc(publish:resolver:rejecter:)
	func publish(_ message: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		do {
			if (self.messageManager == nil) {
				throw GoogleNearbyMessagesError.runtimeError(message: "Google Nearby Messages is not connected! Call connect() before any other calls.")
			}
			self.currentPublication = self.messageManager!.publication(with: GNSMessage(content: message.data(using: .utf8)),
				paramsBlock: { (params: GNSPublicationParams?) in
				  guard let params = params else { return }
				  params.strategy = GNSStrategy(paramsBlock: { (params: GNSStrategyParams?) in
					guard let params = params else { return }
					params.discoveryMediums = .BLE
					params.discoveryMode = .broadcast
				  })
				})
			resolve(nil)
		} catch {
			reject("GOOGLE_NEARBY_MESSAGES_ERROR_PUBLISH", error.localizedDescription, error)
		}
	}
	
	@objc(unpublish:rejecter:)
	func unpublish(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		self.currentPublication = nil
		resolve(nil)
	}
	
	@objc(subscribe:rejecter:)
	func subscribe(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		do {
			if (self.messageManager == nil) {
				throw GoogleNearbyMessagesError.runtimeError(message: "Google Nearby Messages is not connected! Call connect() before any other calls.")
			}
			self.currentSubscription = self.messageManager!.subscription(
				messageFoundHandler: { (message: GNSMessage?) in
					self.sendEvent(withName: EventType.MESSAGE_FOUND.rawValue, body: [ "message": message ]);
				},
				messageLostHandler: { (message: GNSMessage?) in
					self.sendEvent(withName: EventType.MESSAGE_LOST.rawValue, body: [ "message": message ]);
				},
				paramsBlock: { (params: GNSSubscriptionParams?) in
				  guard let params = params else { return }
				  params.strategy = GNSStrategy(paramsBlock: { (params: GNSStrategyParams?) in
					guard let params = params else { return }
					params.discoveryMediums = .BLE
					params.discoveryMode = .scan
				  })
				})
			resolve(nil)
		} catch {
			reject("GOOGLE_NEARBY_MESSAGES_ERROR_SUBSCRIBE", error.localizedDescription, error)
		}
	}
	
	@objc(unsubscribe:rejecter:)
	func unsubscribe(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) -> Void {
		self.currentSubscription = nil
		resolve(nil)
	}
	
	override func supportedEvents() -> [String]! {
		return ["MESSAGE_FOUND", "MESSAGE_LOST", "BLUETOOTH_ERROR", "PERMISSION_ERROR"]
	}
	
	@objc
	override static func requiresMainQueueSetup() -> Bool {
		// init on background thread
		return false
	}
}
