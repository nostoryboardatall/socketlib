//
//  StompClient.swift
//  Pods
//
//  Created by Kuray (FreakyCoder)
//
//

import UIKit
import SocketRocket

struct StompCommands {
    // Basic Commands
    static let commandConnect = "CONNECT"
    static let commandSend = "SEND"
    static let commandSubscribe = "SUBSCRIBE"
    static let commandUnsubscribe = "UNSUBSCRIBE"
    static let commandBegin = "BEGIN"
    static let commandCommit = "COMMIT"
    static let commandAbort = "ABORT"
    static let commandAck = "ACK"
    static let commandDisconnect = "DISCONNECT"
    static let commandPing = "\n"
    
    static let controlChar = String(format: "%C", arguments: [0x00])
    
    // Ack Mode
    static let ackClientIndividual = "client-individual"
    static let ackClient = "client"
    static let ackAuto = "auto"
    // Header Commands
    static let commandHeaderReceipt = "receipt"
    static let commandHeaderDestination = "destination"
    static let commandHeaderDestinationId = "id"
    static let commandHeaderContentLength = "content-length"
    static let commandHeaderContentType = "content-type"
    static let commandHeaderAck = "ack"
    static let commandHeaderTransaction = "transaction"
    static let commandHeaderMessageId = "id"
    static let commandHeaderSubscription = "subscription"
    static let commandHeaderDisconnected = "disconnected"
    static let commandHeaderHeartBeat = "heart-beat"
    static let commandHeaderAcceptVersion = "accept-version"
    // Header Response Keys
    static let responseHeaderSession = "session"
    static let responseHeaderReceiptId = "receipt-id"
    static let responseHeaderErrorMessage = "message"
    // Frame Response Keys
    static let responseFrameConnected = "CONNECTED"
    static let responseFrameMessage = "MESSAGE"
    static let responseFrameReceipt = "RECEIPT"
    static let responseFrameError = "ERROR"
}

public extension String {
    static let sendFrameToCloseSocket = "Send Frame To Close Socket"
}

public enum CloseCodes: Int {
    case manual = -1
    case errorSendFrame = -2
}

public enum StompAckMode {
    case AutoMode
    case ClientMode
    case ClientIndividualMode
}

// Fundamental Protocols
@objc
public protocol StompClientLibDelegate: class {
    func stompClient(client: StompClientLib!,
                     didReceiveMessageWithJSONBody jsonBody: AnyObject?,
                     akaStringBody stringBody: String?,
                     withHeader header:[String:String]?,
                     withDestination destination: String)
    func stompClientDidDisconnect(client: StompClientLib!,
                                  withCode code: Int,
                                  reason: String?,
                                  wasClean: Bool)
    func stompClientDidConnect(client: StompClientLib!)
    func serverDidSendReceipt(client: StompClientLib!,
                              withReceiptId receiptId: String)
    func serverDidSendError(client: StompClientLib!,
                            withErrorMessage description: String,
                            detailedErrorMessage message: String?)
    func didRecievePong(client: StompClientLib!, with data: Data?)
    func serverDidSendPing()
    func didPingServer(client: StompClientLib!, at date: Date)
}

@objcMembers
public class StompClientLib: NSObject, SRWebSocketDelegate {
    var socket: SRWebSocket?
    var sessionId: String?
    weak var delegate: StompClientLibDelegate?
    var connectionHeaders: [String: String]?
    public var connection: Bool = false
    public var certificateCheckEnabled = true
    private var urlRequest: NSURLRequest?
    
    public func sendJSONForDict(dict: AnyObject, toDestination destination: String) {
        do {
            let theJSONData = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions())
            let theJSONText = String(data: theJSONData, encoding: String.Encoding.utf8)
            //print(theJSONText!)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(message: theJSONText!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
        }
    }
    
    public func openSocketWithURLRequest(
        request: NSURLRequest,
        delegate: StompClientLibDelegate,
        connectionHeaders: [String: String]? = nil,
        isDebugEnabled: Bool = false
    ) {
        self.connectionHeaders = connectionHeaders
        self.delegate = delegate
        self.urlRequest = request
        // Opening the socket
        openSocket(isDebugEnabled)
        self.connection = true
    }
    
    private func openSocket(_ isDebugEnabled: Bool = false) {
        if socket == nil || socket?.readyState == .CLOSED {
            if certificateCheckEnabled == true {
                self.socket = SRWebSocket(
                    urlRequest: urlRequest! as URLRequest,
                    isDebugEnabled: isDebugEnabled
                )
            } else {
                self.socket = SRWebSocket(
                    urlRequest: urlRequest! as URLRequest,
                    protocols: [],
                    securityPolicy: SRSecurityPolicy.default(),
                    isDebugEnabled: isDebugEnabled
                )
            }
            socket!.delegate = self
            socket!.open()
        }
    }
    
    private func closeSocket(){
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.stompClientDidDisconnect(client: self,
                                                  withCode: CloseCodes.manual.rawValue,
                                                  reason: nil,
                                                  wasClean: true)
                if self.socket != nil {
                    self.socket!.close()
                    self.socket!.delegate = nil
                    self.socket = nil
                }
            })
        }
    }
    
    /*
     Main Connection Method to open socket
     */
    private func connect() {
        if socket?.readyState == .OPEN {
            // Support for Spring Boot 2.1.x
            if connectionHeaders == nil {
                connectionHeaders = [StompCommands.commandHeaderAcceptVersion:"1.1,1.2"]
            } else {
                connectionHeaders?[StompCommands.commandHeaderAcceptVersion] = "1.1,1.2"
            }
            // at the moment only anonymous logins
            self.sendFrame(command: StompCommands.commandConnect, header: connectionHeaders, body: nil)
        } else {
            self.openSocket()
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceiveMessage message: Any) {
        
        func processString(string: String) {
            var contents = string.components(separatedBy: "\n")
            if contents.first == "" {
                contents.removeFirst()
            }
            
            if let command = contents.first {
                var headers = [String: String]()
                var body = ""
                var hasHeaders  = false
                
                contents.removeFirst()
                for line in contents {
                    if hasHeaders == true {
                        body += line
                    } else {
                        if line == "" {
                            hasHeaders = true
                        } else {
                            let parts = line.components(separatedBy: ":")
                            if let key = parts.first {
                                headers[key] = parts.dropFirst().joined(separator: ":")
                            }
                        }
                    }
                }
                
                // Remove the garbage from body
                if body.hasSuffix("\0") {
                    body = body.replacingOccurrences(of: "\0", with: "")
                }
                
                receiveFrame(command: command, headers: headers, body: body)
            }
        }
        
        if let strData = message as? NSData {
            if let msg = String(data: strData as Data, encoding: String.Encoding.utf8) {
                processString(string: msg)
            }
        } else if let str = message as? String {
            processString(string: str)
        }
    }
    
    public func webSocketDidOpen(_ webSocket: SRWebSocket) {
        connect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.serverDidSendError(
                    client: self,
                    withErrorMessage: error.localizedDescription,
                    detailedErrorMessage: error.localizedDescription
                )
            })
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.stompClientDidDisconnect(client: self, withCode: code, reason: reason, wasClean: wasClean)
            })
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceivePong pongPayload: Data?) {
        guard let delegate = delegate else { return }
        DispatchQueue.main.async(execute: {
            delegate.didRecievePong(client: self, with: pongPayload)
        })
    }
    
    private func sendFrame(command: String?, header: [String: String]?, body: AnyObject?) {
        if socket?.readyState == .OPEN {
            var frameString = ""
            if command != nil {
                frameString = command! + "\n"
            }
            
            if let header = header {
                for (key, value) in header {
                    frameString += key
                    frameString += ":"
                    frameString += value
                    frameString += "\n"
                }
            }
            
            if let body = body as? String {
                frameString += "\n"
                frameString += body
            } else if let _ = body as? NSData {
                
            }
            
            if body == nil {
                frameString += "\n"
            }
            
            frameString += StompCommands.controlChar
            
            if socket?.readyState == .OPEN {
                do {
                    try socket?.send(string: frameString)
                } catch {
                    delegate?.serverDidSendError(
                        client: self,
                        withErrorMessage: error.localizedDescription,
                        detailedErrorMessage: error.localizedDescription
                    )
                }
            } else {
                if let delegate = delegate {
                    DispatchQueue.main.async(execute: {
                        delegate.stompClientDidDisconnect(client: self,
                                                          withCode: CloseCodes.errorSendFrame.rawValue,
                                                          reason: .sendFrameToCloseSocket,
                                                          wasClean: true)
                    })
                }
            }
        }
    }
    
    private func destinationFromHeader(header: [String: String]) -> String {
        for (key, _) in header {
            if key == "destination" {
                let destination = header[key]!
                return destination
            }
        }
        return ""
    }
    
    private func dictForJSONString(jsonStr: String?) -> AnyObject? {
        if let jsonStr = jsonStr {
            do {
                if let data = jsonStr.data(using: String.Encoding.utf8) {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                    return json as AnyObject
                }
            } catch {
                print("error serializing JSON: \(error)")
            }
        }
        return nil
    }
    
    private func receiveFrame(command: String, headers: [String: String], body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession] {
                sessionId = sessId
            }
            
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClientDidConnect(client: self)
                })
            }
        } else if command == StompCommands.responseFrameMessage {   // Message comes to this part
            // Response
            pingServer()
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClient(client: self, didReceiveMessageWithJSONBody: self.dictForJSONString(jsonStr: body), akaStringBody: body, withHeader: headers, withDestination: self.destinationFromHeader(header: headers))
                })
            }
        } else if command == StompCommands.responseFrameReceipt {   //
            // Receipt
            if let delegate = delegate {
                if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendReceipt(client: self, withReceiptId: receiptId)
                    })
                }
            }
        } else if command.count == 0 {
            // Pong from the server
            pingServer()
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.serverDidSendPing()
                })
            }
        } else if command == StompCommands.responseFrameError {
            // Error
            if let delegate = delegate {
                if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendError(client: self, withErrorMessage: msg, detailedErrorMessage: body)
                    })
                }
            }
        }
    }
    
    public func sendMessage(message: String, toDestination destination: String, withHeaders headers: [String: String]?, withReceipt receipt: String?) {
        var headersToSend = [String: String]()
        if let headers = headers {
            headersToSend = headers
        }
        
        // Setting up the receipt.
        if let receipt = receipt {
            headersToSend[StompCommands.commandHeaderReceipt] = receipt
        }
        
        headersToSend[StompCommands.commandHeaderDestination] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headersToSend[StompCommands.commandHeaderContentLength] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headersToSend[StompCommands.commandHeaderContentType] == nil {
            headersToSend[StompCommands.commandHeaderContentType] = "text/plain"
        }
        sendFrame(command: StompCommands.commandSend, header: headersToSend, body: message as AnyObject)
    }
    
    /*
     Main Connection Check Method
     */
    public func isConnected() -> Bool{
        return connection
    }
    
    /*
     Main Subscribe Method with topic name
     */
    public func subscribe(destination: String) {
        connection = true
        subscribeToDestination(destination: destination, ackMode: .AutoMode)
    }
    
    public func subscribeToDestination(destination: String, ackMode: StompAckMode) {
        var ack = ""
        switch ackMode {
        case StompAckMode.ClientMode:
            ack = StompCommands.ackClient
            break
        case StompAckMode.ClientIndividualMode:
            ack = StompCommands.ackClientIndividual
            break
        default:
            ack = StompCommands.ackAuto
            break
        }
        var headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: ""]
        if destination != "" {
            headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: destination]
        }
        self.sendFrame(command: StompCommands.commandSubscribe, header: headers, body: nil)
    }
    
    public func subscribeWithHeader(destination: String, withHeader header: [String: String]) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        sendFrame(command: StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }
    
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(command: StompCommands.commandUnsubscribe, header: headerToSend, body: nil)
    }
    
    public func begin(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandBegin, header: headerToSend, body: nil)
    }
    
    public func commit(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandCommit, header: headerToSend, body: nil)
    }
    
    public func abort(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandAbort, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    /*
     Main Disconnection Method to close the socket
     */
    public func disconnect() {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandDisconnect] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: StompCommands.commandDisconnect, header: headerToSend, body: nil)
        // Close the socket to allow recreation
        self.closeSocket()
    }
    
    // Reconnect after one sec or arg, if reconnect is available
    // TODO: MAKE A VARIABLE TO CHECK RECONNECT OPTION IS AVAILABLE OR NOT
    public func reconnect(
        request: NSURLRequest,
        delegate: StompClientLibDelegate,
        connectionHeaders: [String: String] = [String: String](),
        time: Double = 1.0,
        exponentialBackoff: Bool = true,
        isDebugEnabled: Bool = false
    ){
        if #available(iOS 10.0, *) {
            Timer.scheduledTimer(withTimeInterval: time, repeats: true, block: { _ in
                self.reconnectLogic(
                    request: request,
                    delegate: delegate,
                    connectionHeaders: connectionHeaders,
                    isDebugEnabled: isDebugEnabled
                )
            })
        } else {
            // Fallback on earlier versions
            // Swift >=3 selector syntax
            //            Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.reconnectFallback), userInfo: nil, repeats: true)
            print("Reconnect Feature has no support for below iOS 10, it is going to be available soon!")
        }
    }
    //    @objc func reconnectFallback() {
    //        reconnectLogic(request: request, delegate: delegate, connectionHeaders: connectionHeaders)
    //    }
    
    private func reconnectLogic(
        request: NSURLRequest,
        delegate: StompClientLibDelegate,
        connectionHeaders: [String: String] = [String: String](),
        isDebugEnabled: Bool = false
    ) {
        // Check if connection is alive or dead
        if (!self.isConnected()) {
            if self.checkConnectionHeader(connectionHeaders: connectionHeaders) {
                self.openSocketWithURLRequest(
                    request: request,
                    delegate: delegate,
                    connectionHeaders: connectionHeaders,
                    isDebugEnabled: isDebugEnabled
                )
            } else {
                self.openSocketWithURLRequest(
                    request: request,
                    delegate: delegate,
                    connectionHeaders: nil,
                    isDebugEnabled: isDebugEnabled
                )
            }
        }
    }
    
    private func checkConnectionHeader(connectionHeaders: [String: String] = [String: String]()) -> Bool {
        return !connectionHeaders.isEmpty
    }
    
    private func pingServer() {
        do {
            try socket?.send(string: StompCommands.commandPing)
            delegate?.didPingServer(client: self, at: Date())
        } catch {
            delegate?.serverDidSendError(
                client: self,
                withErrorMessage: error.localizedDescription,
                detailedErrorMessage: "Error sending pong"
            )
        }
    }
    
    // Autodisconnect with a given time
    public func autoDisconnect(time: Double){
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            // Disconnect the socket
            self.disconnect()
        }
    }
}
