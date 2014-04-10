require 'active_support/core_ext/integer/inflections' # ordinalize

module Timely
  module TemporalPatterns
    class Pattern
      attr_reader :intervals, :frequency

      def initialize(ranges, frequency)
        @intervals = Array.wrap(ranges).map { |r| Interval.new(r.first, r.last) }.sort_by(&:first_datetime)
        @frequency = Frequency.new(frequency)
        fix_frequency
      end

      # Convert each interval to a list of datetimes
      def datetimes
        intervals.map do |interval|
          datetimes = []
          datetime = interval.first_datetime
          while datetime <= interval.last_datetime
            datetimes << datetime
            datetime = datetime + frequency.duration
          end
          datetimes
        end
      end

      def ranges
        intervals.map { |i| (i.first_datetime..i.last_datetime) }
      end

      def first_datetime
        surrounding_interval.first_datetime
      end

      def last_datetime
        surrounding_interval.last_datetime
      end

      def surrounding_interval
        Interval.surrounding(intervals)
      end
      alias_method :interval, :surrounding_interval # backwards compatibility

      def match?(datetimes)
        datetimes = Array.wrap(datetimes).map(&:to_datetime)
        intervals.each do |interval|
          current_datetime = interval.first_datetime
          while current_datetime <= interval.last_datetime
            datetimes.delete_if { |datetime| datetime == current_datetime }
            return true if datetimes.empty?
            current_datetime = current_datetime + frequency.duration
          end
        end
        false
      end

      def <=>(other)
        self.intervals.count <=> other.intervals.count
      end

      # Join with other IF same frequency AND same number of intervals
      def join(other)
        return nil unless self.frequency == other.frequency

        expanded_datetimes = self.datetimes.map { |datetimes_within_an_interval|
          back_one    = datetimes_within_an_interval.first - frequency.duration
          forward_one = datetimes_within_an_interval.last + frequency.duration

          [back_one] + datetimes_within_an_interval + [forward_one]
        }

        joint_ranges = []

        # Look for overlaps, where an overlap may be 'off by 1' -- hence the 'expanded_datetimes'
        # ...but start with other and join to each of it's intervals.
        #
        # Remember that 'pattern.datetimes' returns a list of datetimes per interval
        other.datetimes.each do |other_datetimes_within_an_interval|

          joinable_datetimes = expanded_datetimes.find { |expanded_datetimes_within_an_interval|
            other_datetimes_within_an_interval.any? { |d|
              expanded_datetimes_within_an_interval.include?(d)
            }
          }
          break unless joinable_datetimes

          # Joint ranges should be those that overlap
          #
          # This is buggy, because joinable_datetimes is a list of datetimes per interval that overlap
          # Excluding the first doesn't make sense
          #
          # Instead, we should exclude the first AND last for each element within joinable_datetimes 
          joint_datetimes = (other_datetimes_within_an_interval + joinable_datetimes[1...-1]).sort
          joint_ranges << (joint_datetimes.first..joint_datetimes.last)
        end

        # This seems to be trying to say "Only join when we got one for each interval of self"
        # ...it also seems too restrictive...
        #
        # What if other includes multiple intervals of self?
        # Then we don't need same number of intervals
        #
        # Also might be wrong in other ways, it's tricky to tell
        if joint_ranges.size == self.intervals.size
          Pattern.new(joint_ranges, frequency.duration)
        end
      end

      def to_s
        single_date_intervals, multiple_dates_intervals = intervals.partition { |i| i.first_datetime == i.last_datetime}
        patterns_strings = if multiple_dates_intervals.empty?
          single_date_intervals.map(&:to_s)
        else
          interval_surrounding_multiple_dates = Interval.surrounding(multiple_dates_intervals)

          multiple_dates_intervals_string = case frequency.unit
          when :years
            "every #{multiple_dates_intervals.map { |i| "#{i.first_datetime.day.ordinalize} of #{i.first_datetime.strftime('%B')}" }.uniq.to_sentence} #{interval_surrounding_multiple_dates}"
          when :months
            "every #{multiple_dates_intervals.map { |i| i.first_datetime.day.ordinalize }.uniq.to_sentence} of the month #{interval_surrounding_multiple_dates}"
          when :weeks
            weekdays = multiple_dates_intervals.map { |i| i.first_datetime.strftime('%A') }.uniq
            if weekdays.count == 7
              "every day #{interval_surrounding_multiple_dates}"
            else
              "every #{weekdays.to_sentence} #{interval_surrounding_multiple_dates}"
            end
          when :days
            if multiple_dates_intervals.any? { |i| i.first_datetime != i.first_datetime.beginning_of_day }
              "every day at #{multiple_dates_intervals.map { |i| i.first_datetime.strftime("%I:%M %p") }.to_sentence} #{interval_surrounding_multiple_dates}"
            else
              "every day #{interval_surrounding_multiple_dates}"
            end
          else
            "#{frequency} #{multiple_dates_intervals.map(&:to_s).to_sentence}"
          end
          [multiple_dates_intervals_string] + single_date_intervals.map(&:to_s)
        end
        patterns_strings.to_sentence
      end

      private

      # Fix the time units inconsistency problem
      # e.g.: a year isn't exactly 12 months, it's a little bit more, but it is commonly considered to be equal to 12 months
      def fix_frequency
        return unless frequency.duration > 1.month
        if frequency.duration < 12.months
          if intervals.all? { |i| i.first_datetime.day == i.last_datetime.day }
            frequency.duration = frequency.units[:months].months
          end
        else
          if intervals.all? { |i| i.first_datetime.month == i.last_datetime.month && i.first_datetime.day == i.last_datetime.day }
            frequency.duration = (frequency.duration / 12.months).floor.years
          end
        end
      end
    end
  end
end
