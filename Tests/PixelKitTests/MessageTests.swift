import Foundation
import PixelKitProtocol
import Testing

@Test func messagesSurviveArrivingOneByteAtATime() {
    let messages: [Message] = [.frame(width: 2, height: 1, pixels: Data([1, 2, 3, 4, 5, 6, 7, 8])), .keys([123, 49]), .pause, .step, .resume, .keys([])]
    var buffer = Data(), received: [Message] = []
    for byte in messages.map(\.encoded).reduce(Data(), +) { // the worst way reads can split a stream
        buffer.append(byte)
        received += Message.take(from: &buffer)
    }
    #expect(received == messages && buffer.isEmpty)
}
