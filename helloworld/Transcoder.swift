//
//  Transcoder.swift
//  YD
//
//  Created by 안창범 on 2020/09/03.
//  Copyright © 2020 Kewlbear. All rights reserved.
//

import Foundation

class Transcoder {
    var isCancelled = false
    
    var progressBlock: ((Double) -> Void)?
    
    var ifmt_ctx: UnsafeMutablePointer<AVFormatContext>?
    
    var ofmt_ctx: UnsafeMutablePointer<AVFormatContext>?

    struct FilteringContext {
        var buffersink_ctx: UnsafeMutablePointer<AVFilterContext>?
        var buffersrc_ctx: UnsafeMutablePointer<AVFilterContext>?
        var filter_graph: UnsafeMutablePointer<AVFilterGraph>?
    }

    var filter_ctx: [FilteringContext] = []
    
    struct StreamContext {
        var dec_ctx: UnsafeMutablePointer<AVCodecContext>?
        var enc_ctx: UnsafeMutablePointer<AVCodecContext>?
    }
    
    var stream_ctx: [StreamContext] = []

    func open_input_file(filename: String) -> Int32 {
        var ret = avformat_open_input(&ifmt_ctx, filename, nil, nil)
        if ret < 0 {
            print("Cannot open input file")
            return ret
        }
        
        ret = avformat_find_stream_info(ifmt_ctx, nil)
        if ret < 0 {
            print("Cannot find stream info")
            return ret
        }
        
        guard let ic = ifmt_ctx?.pointee else {
            return -19730225
        }
        
        stream_ctx = Array(repeating: StreamContext(), count: Int(ic.nb_streams))
        
        for index in 0..<Int(ic.nb_streams) {
            guard let stream = ic.streams[index] else { return -19730225 }
            guard let dec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id) else {
                print("Failed to find decoder for stream #\(index)")
                return -19730225
            }
            guard let codec_ctx = avcodec_alloc_context3(dec) else {
                print("Failed to allocate the decoder context for stream #\(index)")
                return -19730225
            }
            ret = avcodec_parameters_to_context(codec_ctx, stream.pointee.codecpar)
            if ret < 0 {
                print("Failed to copy decoder parameters to input decoder context for stream #\(index)")
                return ret
            }
            if codec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO || codec_ctx.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                if codec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                    codec_ctx.pointee.framerate = av_guess_frame_rate(ifmt_ctx, stream, nil)
                }
                ret = avcodec_open2(codec_ctx, dec, nil)
                if ret < 0 {
                    print("Failed to open decoder for stream #\(index)")
                    return ret
                }
            }
            stream_ctx[index].dec_ctx = codec_ctx
        }
        
        av_dump_format(ifmt_ctx, 0, filename, 0)
        
        return 0
    }
    
    func open_output_file(filename: String) -> Int32 {
        avformat_alloc_output_context2(&ofmt_ctx, nil, nil, filename)
        guard ofmt_ctx != nil else {
            print("Could not create output context")
            return -19730225
        }
        
        for index in 0..<Int(ifmt_ctx!.pointee.nb_streams) {
            guard let out_stream = avformat_new_stream(ofmt_ctx, nil) else {
                print("Failed allocating output stream")
                return -19730225
            }
            
            guard let in_stream = ifmt_ctx!.pointee.streams[index],
                  let dec_ctx = stream_ctx[index].dec_ctx else
            {
                return -19730225
            }
            
            if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO || dec_ctx.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                guard let encoder = avcodec_find_encoder(AV_CODEC_ID_H264) else { // FIXME: ...
                    print("Necessary encoder not found")
                    return -19730225
                }
                guard let enc_ctx = avcodec_alloc_context3(encoder) else {
                    print("Failed to allocate the encoder context")
                    return -19730225
                }
                
                if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                    enc_ctx.pointee.height = dec_ctx.pointee.height
                    enc_ctx.pointee.width = dec_ctx.pointee.width
                    enc_ctx.pointee.sample_aspect_ratio = dec_ctx.pointee.sample_aspect_ratio
                    enc_ctx.pointee.pix_fmt =
//                        encoder.pointee.pix_fmts?.pointee ??
                        dec_ctx.pointee.pix_fmt
                    enc_ctx.pointee.time_base = av_inv_q(dec_ctx.pointee.framerate)
                } else {
                    enc_ctx.pointee.sample_rate = dec_ctx.pointee.sample_rate
                    enc_ctx.pointee.channel_layout = dec_ctx.pointee.channel_layout
                    enc_ctx.pointee.channels = av_get_channel_layout_nb_channels(enc_ctx.pointee.channel_layout)
                    enc_ctx.pointee.sample_fmt = encoder.pointee.sample_fmts.pointee
                    enc_ctx.pointee.time_base = AVRational(num: 1, den: enc_ctx.pointee.sample_rate)
                }
                
                if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_GLOBALHEADER) != 0) {
                    enc_ctx.pointee.flags |= AVFMT_GLOBALHEADER
                }
                
                var ret = avcodec_open2(enc_ctx, encoder, nil)
                if ret < 0 {
                    print("Cannot open video encoder for stream #\(index)")
                    return ret
                }
                ret = avcodec_parameters_from_context(out_stream.pointee.codecpar, enc_ctx)
                if ret < 0 {
                    print("Failed to copy encoder parameters to output stream #\(index)")
                    return ret
                }
                
                out_stream.pointee.time_base = enc_ctx.pointee.time_base
                stream_ctx[index].enc_ctx = enc_ctx
            } else if dec_ctx.pointee.codec_type == AVMEDIA_TYPE_UNKNOWN {
                print("Elementary stream #\(index) is of unknown type, cannot proceed")
                return -19730225
            } else {
                let ret = avcodec_parameters_copy(out_stream.pointee.codecpar, in_stream.pointee.codecpar)
                if ret < 0 {
                    print("Copying parameters for stream #\(index) failed")
                    return ret
                }
                out_stream.pointee.time_base = in_stream.pointee.time_base
            }
        }
        av_dump_format(ofmt_ctx, 0, filename, 1)
        
        if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_NOFILE) == 0) {
            let ret = avio_open(&ofmt_ctx!.pointee.pb, filename, AVIO_FLAG_WRITE)
            if ret < 0 {
                print("Could not open output file '\(filename)'")
                return ret
            }
        }
        
        let ret = avformat_write_header(ofmt_ctx, nil)
        if ret < 0 {
            print("Error occurred when opening output file")
            return ret
        }
        
        return 0
    }
    
    func init_filters() -> Int32 {
        guard let ifmt_ctx = self.ifmt_ctx else {
            return -9999
        }
        filter_ctx = Array(repeating: FilteringContext(), count: Int(ifmt_ctx.pointee.nb_streams))
        
        for index in 0..<Int(ifmt_ctx.pointee.nb_streams) {
            let codec_type = ifmt_ctx.pointee.streams[index]?.pointee.codecpar.pointee.codec_type
            guard [AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO].contains(codec_type) else {
                continue
            }
            var filter_spec: String
            if codec_type == AVMEDIA_TYPE_VIDEO {
                filter_spec = "null"
            } else {
                filter_spec = "null"
            }
            let ret = init_filter(fctx: &filter_ctx[index], dec_ctx: stream_ctx[index].dec_ctx!, enc_ctx: stream_ctx[index].enc_ctx!, filter_spec: filter_spec)
            guard ret == 0 else {
                return ret
            }
        }
        
        return 0
    }
    
    func init_filter(fctx: UnsafeMutablePointer<FilteringContext>, dec_ctx: UnsafePointer<AVCodecContext>, enc_ctx: UnsafeMutablePointer<AVCodecContext>, filter_spec: String) -> Int32 {
        var outputs: UnsafeMutablePointer<AVFilterInOut>? = avfilter_inout_alloc()
        defer {
            avfilter_inout_free(&outputs)
        }
        var inputs: UnsafeMutablePointer<AVFilterInOut>? = avfilter_inout_alloc()
        defer {
            avfilter_inout_free(&inputs)
        }
        guard outputs != nil && inputs != nil,
              let filter_graph = avfilter_graph_alloc() else
        {
            return -999
        }
        
        var buffersrc_ctx: UnsafeMutablePointer<AVFilterContext>?
        var buffersink_ctx: UnsafeMutablePointer<AVFilterContext>?

        switch dec_ctx.pointee.codec_type {
        case AVMEDIA_TYPE_VIDEO:
            guard let buffersrc = avfilter_get_by_name("buffer"),
                  let buffersink = avfilter_get_by_name("buffersink") else
            {
                print("filtering source or sink element not found")
                return -999
            }
            let args = "video_size=\(dec_ctx.pointee.width)x\(dec_ctx.pointee.height):pix_fmt=\(dec_ctx.pointee.pix_fmt.rawValue):time_base=\(dec_ctx.pointee.time_base.num)/\(dec_ctx.pointee.time_base.den):pixel_aspect=\(dec_ctx.pointee.sample_aspect_ratio.num)/\(dec_ctx.pointee.sample_aspect_ratio.den)"
            
            var ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in", args, nil, filter_graph)
            if ret < 0 {
                print("Cannot create buffer source")
                return ret
            }
            
            ret = avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out", nil, nil, filter_graph)
            if ret < 0 {
                print("Cannot create buffer sink")
                return ret
            }
            
            let size = MemoryLayout<AVPixelFormat>.size
            withUnsafePointer(to: enc_ctx.pointee.pix_fmt) {
                $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                    ret = av_opt_set_bin(buffersink_ctx, "pix_fmts", $0, Int32(size), AV_OPT_SEARCH_CHILDREN)
                }
            }
            if ret < 0 {
                return ret
            }
        default:
            fatalError()
        }
        
        outputs?.pointee.name = strdup("in")
        outputs?.pointee.filter_ctx = buffersrc_ctx
        outputs?.pointee.pad_idx = 0
        outputs?.pointee.next = nil
        
        inputs?.pointee.name = strdup("out")
        inputs?.pointee.filter_ctx = buffersink_ctx
        inputs?.pointee.pad_idx = 0
        inputs?.pointee.next = nil
        
        var ret = avfilter_graph_parse_ptr(filter_graph, filter_spec, &inputs, &outputs, nil)
        if ret < 0 {
            return ret
        }
        
        ret = avfilter_graph_config(filter_graph, nil)
        if ret < 0 {
            return ret
        }
        
        fctx.pointee.buffersrc_ctx = buffersrc_ctx
        fctx.pointee.buffersink_ctx = buffersink_ctx
        fctx.pointee.filter_graph = filter_graph
        
        return 0
    }
    
    func filter_encode_write_frame(frame: UnsafeMutablePointer<AVFrame>?, stream_index: Int) -> Int32 {
        var ret = av_buffersrc_add_frame_flags(filter_ctx[stream_index].buffersrc_ctx, frame, 0)
        if ret < 0 {
            print("Error while feeding the filtergraph")
            return ret
        }
        
        while true {
            var filt_frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
            guard filt_frame != nil else {
                return -999
            }
            ret = av_buffersink_get_frame(filter_ctx[stream_index].buffersink_ctx, filt_frame)
            if ret < 0 {
                av_frame_free(&filt_frame)
                return (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) ? 0 : ret
            }
            
            filt_frame?.pointee.pict_type = AV_PICTURE_TYPE_NONE
            var got_frame: Int32 = 0
            ret = encode_write_frame(filt_frame: &filt_frame, stream_index: stream_index, got_frame: &got_frame)
            if ret < 0 {
                return ret
            }
        }
    }

    func encode_write_frame(filt_frame: UnsafeMutablePointer<UnsafeMutablePointer<AVFrame>?>?, stream_index: Int, got_frame: inout Int32) -> Int32 {
        var enc_pkt = AVPacket()
        av_init_packet(&enc_pkt)
        let ret = avcodec_encode_video2(stream_ctx[stream_index].enc_ctx, &enc_pkt, filt_frame?.pointee, &got_frame)
        av_frame_free(filt_frame)
        if ret < 0 {
            return ret
        }
        if got_frame == 0 {
            return 0
        }
        
        enc_pkt.stream_index = Int32(stream_index)
        av_packet_rescale_ts(&enc_pkt, stream_ctx[stream_index].enc_ctx!.pointee.time_base, ofmt_ctx!.pointee.streams[stream_index]!.pointee.time_base)
        
        return av_interleaved_write_frame(ofmt_ctx, &enc_pkt)
    }
    
    func flush_encoder(stream_index: Int) -> Int32 {
        guard (stream_ctx[stream_index].enc_ctx!.pointee.codec.pointee.capabilities & AV_CODEC_CAP_DELAY) != 0 else {
            return 0
        }
        
        while true {
            print("Flushing stream #\(stream_index) encoder")
            var got_frame: Int32 = 0
            let ret = encode_write_frame(filt_frame: nil, stream_index: stream_index, got_frame: &got_frame)
            if ret < 0 {
                return ret
            }
            if got_frame == 0 {
                return 0
            }
        }
    }
    
    func transcode(from: URL, to url: URL) -> Int32 {
        var ret = open_input_file(filename: from.path)
        if ret < 0 {
            return ret
        }

        ret = open_output_file(filename: url.path)
        if ret < 0 {
            return ret
        }

        ret = init_filters()
        if ret < 0 {
            return ret
        }
        
        var packet = AVPacket()
        
        let formatter = DateComponentsFormatter()
        let AV_TIME_BASE: Int32 = 1000_000
        let AV_TIME_BASE_Q = AVRational(num: 1, den: AV_TIME_BASE)
        
        while !isCancelled {
            ret = av_read_frame(ifmt_ctx, &packet)
            if ret < 0 {
                break
            }
            let stream_index = Int(packet.stream_index)
            let type = ifmt_ctx?.pointee.streams[stream_index]?.pointee.codecpar.pointee.codec_type
            
            var frame = av_frame_alloc()
            guard frame != nil else {
                return ret
            }
            av_packet_rescale_ts(&packet, ifmt_ctx!.pointee.streams[stream_index]!.pointee.time_base, stream_ctx[stream_index].dec_ctx!.pointee.time_base)
            let dec_func = type == AVMEDIA_TYPE_VIDEO ? avcodec_decode_video2 : avcodec_decode_audio4
            var got_frame: Int32 = 0
            ret = dec_func(stream_ctx[stream_index].dec_ctx, frame!, &got_frame, &packet)
            if ret < 0 {
                av_frame_free(&frame)
                print("Decoding failed")
                return ret
            }
            
            if got_frame != 0 {
                frame?.pointee.pts = frame!.pointee.best_effort_timestamp
                ret = filter_encode_write_frame(frame: frame, stream_index: stream_index)
                av_frame_free(&frame)
                if ret < 0 {
                    return ret
                }

                if progressBlock != nil,
                   let duration = ifmt_ctx?.pointee.duration,
                   let stream = ofmt_ctx?.pointee.streams[stream_index] {
                    let pts = av_rescale_q(av_stream_get_end_pts(stream), stream.pointee.time_base, AV_TIME_BASE_Q)
                    let progress = Double(pts) / Double(duration)
                    
                    let t = TimeInterval(pts) / TimeInterval(AV_TIME_BASE)
                    print(#function, "time =", formatter.string(from: t) ?? "?", progress)
                    
                    progressBlock?(progress)
                }
            } else {
                av_frame_free(&frame)
            }
            av_packet_unref(&packet)
        }

        for index in 0..<Int(ifmt_ctx!.pointee.nb_streams) {
            if filter_ctx[index].filter_graph == nil {
                continue
            }
            ret = filter_encode_write_frame(frame: nil, stream_index: index)
            if ret < 0 {
                print("Flushing filter failed")
                return ret
            }
            
            ret = flush_encoder(stream_index: index)
            if ret < 0 {
                print("Flushing encoder failed")
                return ret
            }
        }
        
        av_write_trailer(ofmt_ctx)
        
        av_packet_unref(&packet)
        for index in 0..<Int(ifmt_ctx?.pointee.nb_streams ?? 0) {
            avcodec_free_context(&stream_ctx[index].dec_ctx)
            if ofmt_ctx?.pointee.nb_streams ?? 0 > index && ofmt_ctx?.pointee.streams[index] != nil && (stream_ctx[index].enc_ctx != nil) {
                avcodec_free_context(&stream_ctx[index].enc_ctx)
            }
            if filter_ctx[index].filter_graph != nil {
                avfilter_graph_free(&filter_ctx[index].filter_graph)
            }
        }
        avformat_close_input(&ifmt_ctx)
        if (((ofmt_ctx?.pointee.oformat.pointee.flags ?? 0) & AVFMT_NOFILE) == 0) {
            avio_closep(&ofmt_ctx!.pointee.pb)
        }
        avformat_free_context(ofmt_ctx)
        
        if ret < 0 {
            var buffer: [Int8] = Array(repeating: 0, count: 1024)
            let message = String(utf8String: av_make_error_string(&buffer, buffer.count, ret))
            print("Error occurred: \(message ?? "nil?")")
        }
        
        return ret
    }
}

func AVERROR(_ e: Int32) -> Int32 {
    -e
}

let AVERROR_EOF: Int32 = -541478725
