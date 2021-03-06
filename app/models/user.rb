# encoding: utf-8

class User < ActiveRecord::Base

  devise :database_authenticatable, :registerable, :confirmable, :lockable,
         :recoverable, :rememberable, :trackable, :omniauthable

  attr_accessible :email, :password, :password_confirmation, :remember_me,
                  :name, :first_name, :middle_name, :last_name, :location, :phone, :urls, :birth_date

  serialize :urls

  belongs_to :organization

  has_many :authentications, dependent: :destroy
  has_many :device_messages, dependent: :destroy
  has_many :user_messages, dependent: :destroy, order: :timestamp
  has_one :referral, class_name: "WatcherReferral", dependent: :destroy
  has_many :media_items
  has_many :locations, class_name: "UserLocation", dependent: :destroy, order: :created_at
  has_many :commissions, through: :locations
  has_many :device_messages, dependent: :destroy
  has_many :watcher_reports, dependent: :destroy
  has_many :sos_messages, dependent: :destroy

  WATCHER_STATUSES = %W(pending approved rejected problem blocked none)
  WATCHER_KINDS = ["Участник голосования", "Наблюдатель", "Член УИК с ПСГ", "Член УИК с ПРГ", "Член ТИК с ПСГ", "Член ТИК с ПРГ", "Представитель прессы"]

  scope :admins, where(role: "admin")
  scope :moderators, where(role: "moderators")
  scope :partners, where(role: "partner")
  scope :watchers, where(is_watcher: true)

  WATCHER_STATUSES.each do |status|
    class_eval <<-EOF
    scope :#{status}, watchers.where(status: :#{status})

    EOF
  end

  validates :email, :name, :first_name, :middle_name, :last_name, :location, :phone, length: { maximum: 255 }
  validates :watcher_status, inclusion: { in: WATCHER_STATUSES }

  after_initialize  :set_default_watcher_status
  after_save        :update_watcher_reports

  def self.active_count
    @active_count ||= DeviceMessage.count(:user_id, distinct: true)
  end

  def watcher_status
    ActiveSupport::StringInquirer.new("#{read_attribute(:watcher_status)}")
  end

  def set_watcher_kind(kind_index)
    self.watcher_kind = WATCHER_KINDS[kind_index.to_i]
  end

  # TODO: Maybe we need to cache it in DB. Change order.
  def current_location
    @current_location ||= locations.order("created_at DESC").first
  end

  # TODO: Maybe we need to cache it in DB
  def current_commission
    @current_commission ||= current_location.try(:commission)
  end

  def has_email?
    email.present? || unconfirmed_email.present?
  end

  def to_s
    name.presence || email.presence || authentications.first.to_s
  end

  def full_watcher_kind
    if WATCHER_KINDS.index(watcher_kind) != 0
      if watcher_status.approved?
        "#{watcher_kind} (подтверждено)"
      else
        "#{watcher_kind} (ожидает подтверждения)"
      end
    else
      watcher_kind
    end
  end

  def apply_omniauth(omniauth)
    extract_omniauth_data(omniauth)
    authentications.build(
        provider: omniauth['provider'],
        uid: omniauth['uid'],
        token: omniauth['credentials']['token'],
        secret: omniauth['credentials']['secret']
    )
  end


  # Reimplement Devise::Models::Validatable here since we need to tweak uniqueness validation conditions
  validates_presence_of   :email, :if => :email_required?
  validates_uniqueness_of :email, :allow_blank => true, :if => :email_uniqueness_required?
  validates_format_of     :email, :with  => Devise.email_regexp, :allow_blank => true, :if => :email_changed?

  validates_presence_of     :password, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?
  validates_length_of       :password, :within => Devise.password_length, :allow_blank => true

  def password_required?
    (authentications.empty? || !password.blank?) && (!persisted? || !password.nil? || !password_confirmation.nil?)
  end

  def email_required?
    true
  end

  # Skip email uniqueness validation for users registered through mobile applications since they might want
  # to connect their devices to existing accounts. We skip it for postponed email changes only.
  #
  # Refer to Devise::Models::Confirmable for more info.
  def email_uniqueness_required?
    email_changed? && (@bypass_postpone || new_record? || !Authentication.reserved_device_email?(email_was))
  end
  # End of Devise::Models::Validatable

  protected

  def extract_omniauth_data(omniauth)
    %W(email name first_name last_name location phone).each do |attr|
      self[attr] = omniauth['info'][attr] if self[attr].blank?
    end

    self.urls ||= {}
    self.urls.reverse_merge!(omniauth['info']['urls'].presence || {})
  end

  def set_default_watcher_status
    self.watcher_status = "none" if self.watcher_status.blank?
  end

  def update_watcher_reports
    return unless self.watcher_status_changed?

    if self.watcher_status == "approved"
      self.watcher_reports.each {|r| r.save! }
    elsif self.watcher_status == "rejected"
      self.watcher_reports.update_all(status: "rejected")
    elsif self.watcher_status == "problem"
      self.watcher_reports.update_all(status: "problem")
    elsif self.watcher_status == "blocked"
      self.watcher_reports.update_all(status: "blocked")
    end
  end
end
