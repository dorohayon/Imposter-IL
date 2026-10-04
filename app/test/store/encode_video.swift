// Encodes the preview: the rendered frames and the mixed soundtrack into an
// MP4 the App Store takes (886×1920, 30 fps, H.264 High 4.0 at ~10 Mbps,
// 256 kbps stereo AAC). docs/store-assets.md.
//
//   swift test/store/encode_video.swift build/store/video/en out.mp4
//
// Run from app/: it mixes the soundtrack from assets/sounds first.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count == 3 else {
  print("usage: encode_video.swift <frames folder> <out.mp4>")
  exit(2)
}
let folder = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: output)

let frames = try FileManager.default.contentsOfDirectory(atPath: folder.path)
  .filter { $0.hasPrefix("frame_") && ($0.hasSuffix(".png") || $0.hasSuffix(".jpg")) }
  .sorted()
let fps: Int32 = 30
let width = 886
let height = 1920

let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: width,
  AVVideoHeightKey: height,
  AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: 10_000_000,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
    AVVideoExpectedSourceFrameRateKey: fps,
    AVVideoMaxKeyFrameIntervalKey: fps,
  ],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
  assetWriterInput: video,
  sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
  ])
writer.add(video)

// The soundtrack: the game's own sounds (assets/sounds) at the moments the
// render recorded in sounds.json, mixed into a stereo WAV beside the frames.
// A sound with "until" repeats until then ("Time to vote" round its screen).
struct Cue: Decodable {
  let t: Double
  let file: String
  let until: Double?
}
struct Cues: Decodable {
  let fps: Double
  let frames: Int
  let sounds: [Cue]
}
let cues = try JSONDecoder().decode(
  Cues.self, from: Data(contentsOf: folder.appendingPathComponent("sounds.json")))
let rate = 44100.0
let length = Int(Double(cues.frames) / cues.fps * rate)
var left = [Float](repeating: 0, count: length)
var right = [Float](repeating: 0, count: length)
for cue in cues.sounds {
  let file = try AVAudioFile(forReading: URL(fileURLWithPath: "assets/sounds/\(cue.file).m4a"))
  precondition(file.processingFormat.sampleRate == rate, "\(cue.file) is not 44.1 kHz")
  let buffer = AVAudioPCMBuffer(
    pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
  try file.read(into: buffer)
  let n = Int(buffer.frameLength)
  let channels = buffer.floatChannelData!
  let stereo = file.processingFormat.channelCount > 1
  let start = Int(cue.t * rate)
  let end = min(length, cue.until.map { Int($0 * rate) } ?? start + n)
  for i in start..<max(start, end) {
    let k = (i - start) % n
    left[i] += channels[0][k] * 0.8
    right[i] += channels[stereo ? 1 : 0][k] * 0.8
  }
}
let peak = max(1, (left + right).map(abs).max() ?? 1)
let mixFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
let mix = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: AVAudioFrameCount(length))!
mix.frameLength = AVAudioFrameCount(length)
for i in 0..<length {
  mix.floatChannelData![0][i] = left[i] / peak
  mix.floatChannelData![1][i] = right[i] / peak
}
let wav = folder.appendingPathComponent("audio.wav")
try? FileManager.default.removeItem(at: wav)
do {
  let out = try AVAudioFile(forWriting: wav, settings: [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: rate,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16,
  ])
  try out.write(from: mix)
}

let audioAsset = AVURLAsset(url: wav)
let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
let reader = try AVAssetReader(asset: audioAsset)
let pcm = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
  AVFormatIDKey: kAudioFormatLinearPCM,
  AVLinearPCMBitDepthKey: 16,
  AVLinearPCMIsFloatKey: false,
  AVLinearPCMIsBigEndianKey: false,
  AVLinearPCMIsNonInterleaved: false,
])
reader.add(pcm)
let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
  AVFormatIDKey: kAudioFormatMPEG4AAC,
  AVSampleRateKey: 44100,
  AVNumberOfChannelsKey: 2,
  AVEncoderBitRateKey: 256_000,
])
writer.add(audio)

reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

func pixelBuffer(_ url: URL) -> CVPixelBuffer {
  let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
  var buffer: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
  let pb = buffer!
  CVPixelBufferLockBaseAddress(pb, [])
  let context = CGContext(
    data: CVPixelBufferGetBaseAddress(pb), width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
      | CGBitmapInfo.byteOrder32Little.rawValue)!
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  CVPixelBufferUnlockBaseAddress(pb, [])
  return pb
}

let group = DispatchGroup()
group.enter()
var next = 0
video.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
  while video.isReadyForMoreMediaData {
    if next == frames.count {
      video.markAsFinished()
      group.leave()
      return
    }
    let time = CMTime(value: CMTimeValue(next), timescale: fps)
    adaptor.append(pixelBuffer(folder.appendingPathComponent(frames[next])), withPresentationTime: time)
    next += 1
  }
}
group.enter()
audio.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
  while audio.isReadyForMoreMediaData {
    guard let sample = pcm.copyNextSampleBuffer() else {
      audio.markAsFinished()
      group.leave()
      return
    }
    audio.append(sample)
  }
}
await withCheckedContinuation { done in group.notify(queue: .global()) { done.resume() } }
await writer.finishWriting()
if writer.status != .completed {
  print("failed:", writer.error.map { "\($0)" } ?? "unknown")
  exit(1)
}
print(output.path, frames.count, "frames")
