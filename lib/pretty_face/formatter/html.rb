require 'erb'
require 'fileutils'
require 'cucumber/formatter/io'
require 'cucumber/formatter/duration'
require 'cucumber/ast/scenario'
require 'cucumber/ast/table'
require 'cucumber/ast/outline_table'
require File.join(File.dirname(__FILE__), 'view_helper')
require File.join(File.dirname(__FILE__), 'report')

module PrettyFace
  module Formatter

    class Html
      include Cucumber::Formatter::Io
      include Cucumber::Formatter::Duration
      include ViewHelper

      def initialize(step_mother, path_or_io, options)
        @path = path_or_io
        @io = ensure_io(path_or_io, 'html')
        @step_mother = step_mother
        @options = options
        @report = Report.new
        @img_id = 0
      end

      def embed(src, mime_type, label)
        case(mime_type)
        when /^image\/(png|gi|jpg|jpeg)/
          embed_image(src, label)
        end
      end

      def embed_image(src, image)
        id = "img_#{@img_id}"
        @img_id += 1
      end

      def before_features(features)
        @tests_started = Time.now
      end

      def before_feature(feature)
        @report.add_feature ReportFeature.new(feature)
      end

      def after_feature(feature)
        @report.current_feature.close(feature)
      end
      
      def before_background(background)
        @report.begin_background
      end

      def after_background(background)
        @report.end_background
      end

      def before_feature_element(feature_element)
        unless scenario_outline? feature_element
          @report.add_scenario  ReportScenario.new(feature_element)
        end
      end

      def after_feature_element(feature_element)
        unless scenario_outline?(feature_element)
          process_scenario(feature_element)
        end
      end

      def before_table_row(example_row)
        @report.add_scenario ReportScenario.new(example_row) unless info_row?(example_row)
      end

      def after_table_row(example_row)
        unless info_row?(example_row)
          @report.current_scenario.populate(example_row)
          build_scenario_outline_steps(example_row)
        end
        populate_cells(example_row) if example_row.instance_of? Cucumber::Ast::Table::Cells
      end

      def before_step(step)
        @step_timer = Time.now
      end

      def after_step(step)
        step = process_step(step) unless step_belongs_to_outline? step
        if @cells
          step.table = @cells
          @io.puts "#{@cells} <br />"
          @cells = nil
        end
      end

      def after_features(features)
        @features = features
        @duration = format_duration(Time.now - @tests_started)
        generate_report
        copy_images_directory
        copy_stylesheets_directory
      end

      def features
        @report.features
      end

      private

      def generate_report
        filename = File.join(File.dirname(__FILE__), '..', 'templates', 'main.erb')
        text = File.new(filename).read
        @io.puts ERB.new(text, nil, "%>").result(binding)
        erbfile = File.join(File.dirname(__FILE__), '..', 'templates', 'feature.erb')
        text = File.new(erbfile).read
        features.each do |feature|
          write_feature_file(feature, text)
        end
      end

      def write_feature_file(feature, text)
          file = File.open("#{File.dirname(@path)}/#{feature.file}", Cucumber.file_mode('w'))
          file.puts ERB.new(text, nil, "%").result(feature.get_binding)
          file.flush
          file.close
      end

      def copy_directory(target_path, file_names, file_extension)
        path = "#{File.dirname(@path)}/#{target_path}"
        FileUtils.mkdir path unless File.directory? path
        file_names.each do |file|
          FileUtils.cp File.join(File.dirname(__FILE__), '..', 'templates', "#{file}.#{file_extension}"), path
        end
      end

      def copy_images_directory
        copy_directory "images", %w(face failed passed pending undefined skipped), "jpg"
      end

      def copy_stylesheets_directory
        copy_directory "stylesheets", ['style'], 'css'
      end

      def process_scenario(scenario)
        @report.current_scenario.populate(scenario)
      end

      def process_step(step, status=nil)
        duration =  Time.now - @step_timer
        step = ReportStep.new(step)
        step.duration = duration
        step.status = status unless status.nil?
        @report.add_step step unless @report.processing_background_steps?
        step
      end

      def scenario_outline?(feature_element)
        feature_element.is_a? Cucumber::Ast::ScenarioOutline
      end

      def info_row?(example_row)
        return example_row.scenario_outline.nil? if example_row.respond_to? :scenario_outline
        return true if example_row.instance_of? Cucumber::Ast::Table::Cells
        false
      end

      def step_belongs_to_outline?(step)
        scenario = step.instance_variable_get "@feature_element"
        not scenario.nil?
      end

      def build_scenario_outline_steps(example_row)
        values = example_row.to_hash
        steps = example_row.scenario_outline.raw_steps.clone
        steps.each do |step|
          name = nil
          values.each do |key, value|
            name = step.name.gsub("<#{key}>", "'#{value}'") if step.name.include? "<#{key}>"
          end
          current_step = process_step(step, example_row.status)
          current_step.name = name if name
          current_step.error = step_error(example_row.exception, step)
        end
      end
      
      def step_error(exception, step)
        return nil if exception.nil?
        exception.backtrace[-1] =~ /^#{step.file_colon_line}/ ? exception : nil
      end

      def populate_cells(example_row)
        @cells ||= []
        values = []
        example_row.to_a.each do |cell|
          values << cell.value
        end
        @cells << values
      end
    end
  end
end
