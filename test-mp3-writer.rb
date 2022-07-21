# frozen_string_literal: true

require 'ostruct'
require 'fileutils'
require 'taglib'

class AudioFile
  def path
    'output.mp3'
  end

  def duration
    60
  end
end

class Mp3ChapterWriter
  attr_reader :audio, :metadata

  def initialize(audio, metadata)
    @audio = audio
    @metadata = metadata
  end

  def call
    write_chapters
    audio
  end

  def write_chapters
    TagLib::MPEG::File.open(audio.path) do |file|
      tag = file.id3v2_tag

      tag.title = "changed at #{Time.now}"

      remove_toc(tag)
      remove_chapters(tag)

      chapter_marks.each_with_index do |chapter, index|
        tag.add_frame(build_chapter(chapter, index))
      end
      tag.add_frame(build_toc)

      file.save
    end
  end

  private

  def remove_chapters(tag)
    return unless tag.frame_list('CHAP').any?

    tag.frame_list('CHAP').each do |frame|
      tag.remove_frame(frame)
    end
  end

  def remove_toc(tag)
    return unless tag.frame_list('CTOC').any?

    tag.frame_list('CTOC').each do |frame|
      tag.remove_frame(frame)
    end
  end

  def build_chapter(chapter, idx)
    chapter_frame = TagLib::ID3v2::ChapterFrame.new(
      chapter_element_id(idx),
      chapter['start'].to_i,
      chapter['end'].to_i,
      0xFFFFFFFF, # using this as the byte offset leads to ignoring it
      0xFFFFFFFF  # and using the start/end times
    )

    frames = build_embedded_frames(chapter)

    frames.each do |frame|
      chapter_frame.add_embedded_frame(frame)
    end

    chapter_frame
  end

  def build_embedded_frames(chapter)
    [
      build_title_frame(chapter['title']),
      build_url_frame(chapter['url']),
      build_image_frame(chapter['image_mime'], chapter['image_data'])
    ].compact
  end

  def build_title_frame(text)
    TagLib::ID3v2::TextIdentificationFrame.new(
      'TIT2',
      TagLib::String::UTF8
    ).tap { |text_id_frame| text_id_frame.text = text }
  end

  def build_url_frame(url)
    TagLib::ID3v2::UserUrlLinkFrame.new.tap do |url_frame|
      url_frame.description = 'chapter URL'
      url_frame.url = url
    end
  end

  def build_image_frame(mime_type, data)
    return unless data

    TagLib::ID3v2::AttachedPictureFrame.new.tap do |image_frame|
      image_frame.mime_type = mime_type
      image_frame.text_encoding = TagLib::String::Latin1
      image_frame.type = TagLib::ID3v2::AttachedPictureFrame::Other
      image_frame.picture = data
    end
  end

  def build_toc
    toc = TagLib::ID3v2::TableOfContentsFrame.new('TOC')
    toc.is_top_level = true
    toc.is_ordered = true

    chapter_marks.each_with_index do |_chapter_info, index|
      toc.add_child_element(chapter_element_id(index))
    end

    toc
  end

  def chapter_element_id(chap_num)
    "CH#{chap_num + 1}"
  end

  # https://id3.org/id3v2-chapters-1.0#Chapter_frame
  def chapter_marks # rubocop:disable Metrics/AbcSize
    chapters = metadata.chapter_marks || []

    chapters.each_with_object([]) do |chapter, result|
      data = chapter.dup
      data['start'] = chapter_time_to_millisec(data['start'])
      data['end'] = chapter_time_to_millisec(data['end']) || (audio.duration * 1000)
      data['image_data'] = File.binread('chap.jpg')
      data['image_mime'] = 'image/jpeg'

      # remove empty values
      result << data.reject do |_k, v|
        v.nil?
      end
    end
  end

  def chapter_time_to_millisec(str)
    return if str.nil?

    integers = str.split(':').reverse
    integers.each_with_index.inject(0) do |sum, (digit, index)|
      sum + ((digit.to_i * 60.pow(index)) * 1000)
    end
  end
end

FileUtils.cp('input.mp3', 'output.mp3')

audio = AudioFile.new

writer = \
  Mp3ChapterWriter.new(
    audio,
    OpenStruct.new(
      chapter_marks: [
        {
          'start' => '00:00:03',
          'end' => '00:00:05'
        }
      ]
    )
  )

writer.call
