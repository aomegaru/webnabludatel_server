# encoding: utf-8

class DeviceMessage < ActiveRecord::Base
  attr_accessible :message
  serialize :message

  belongs_to :user

  has_one :watcher_report, dependent: :destroy

  after_save :set_watcher_report


  private
    def set_watcher_report
      watcher_report = self.watcher_report || WatcherReport.new
      watcher_report.device_message = self

      watcher_report.recorded_at = Time.at(self.message["timestamp"].to_i)
      watcher_report.user = self.user

      watcher_report.comission = self.user.current_comission

      watcher_report.key = self.message["key"]
      watcher_report.value = self.message["value"]

      watcher_report.save!
    end

end