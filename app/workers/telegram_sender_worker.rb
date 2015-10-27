class TelegramSenderWorker
  include Sidekiq::Worker
  TELEGRAM_SENDER_LOG = Logger.new(Rails.root.join('log/intouch', 'telegram-sender.log'))

  def perform(issue_id, state)
    Intouch.set_locale
    issue = Issue.find issue_id

    base_message = issue.telegram_message

    token = Setting.plugin_redmine_intouch['telegram_bot_token']
    bot = Telegrammer::Bot.new(token)

    issue.intouch_recipients('telegram', state).each do |user|
      telegram_user = user.telegram_user
      next unless telegram_user.present? and telegram_user.active?

      message = if issue.assigned_to_id == user.id
                  "#{I18n.t('intouch.telegram_message.recipient.assignee')}\n#{base_message}"
                elsif issue.watchers.pluck(:user_id).include? user.id
                  "#{I18n.t('intouch.telegram_message.recipient.watcher')}\n#{base_message}"
                elsif issue.author_id == user.id
                  "#{I18n.t('intouch.telegram_message.recipient.author')}\n#{base_message}"
                else
                  base_message
                end

      begin
        bot.send_message(chat_id: telegram_user.tid, text: message, disable_web_page_preview: true)
      rescue Telegrammer::Errors::BadRequestError => e
        if e.message.include? 'Bot was kicked'
          telegram_user.deactivate
          TELEGRAM_SENDER_LOG.info "Bot was kicked from chat. Deactivate #{telegram_user.inspect}"
        else
          TELEGRAM_SENDER_LOG.error "#{e.class}: #{e.message}"
          TELEGRAM_SENDER_LOG.debug "#{issue.inspect}"
          TELEGRAM_SENDER_LOG.debug "#{user.inspect}"
          TELEGRAM_SENDER_LOG.debug "#{telegram_user.inspect}"
        end
      end
    end
  end

end
