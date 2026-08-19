# Shared premium HTML shell for every outbound transactional email (OTP
# verification, password reset, temporary password, agent/RAM approval —
# models/client.rb, models/agent.rb, models/ram_member.rb, models/user.rb).
# Keeps the branded chrome (logo header, card, footer) in one place so it
# can't drift between models, while each caller still owns its own
# subject/body copy.
module App
  module MailerTemplate
    LOGO_PATH = File.join(App.root, 'src', 'assets', 'logo.png')

    BRAND = {
      primary: '#8a3324',
      ink: '#1c1b1a',
      muted: '#6b6b6b',
      border: '#e5e2df',
      page_bg: '#f5f4f2',
      card_bg: '#ffffff',
      code_bg: '#f5f1ee',
    }.freeze

    # Attaches the inline logo and sets `mail.html_part` to the branded shell
    # wrapped around `body_html`. `cta` is an optional {label:, url:} that
    # renders as a pill-shaped button between the body and the footer.
    def self.brand!(mail, preheader:, body_html:, cta: nil, footnote: nil)
      mail.attachments.inline['rerock-logo.png'] = File.binread(LOGO_PATH)
      logo_cid = mail.attachments['rerock-logo.png'].url

      cta_html = cta ? <<~HTML : ''
        <tr>
          <td align="center" style="padding: 4px 32px 4px;">
            <a href="#{cta[:url]}" style="display:inline-block; background:#{BRAND[:primary]}; color:#ffffff; font-family:Helvetica,Arial,sans-serif; font-size:15px; font-weight:bold; text-decoration:none; padding:14px 34px; border-radius:999px; letter-spacing:0.2px;">#{cta[:label]}</a>
          </td>
        </tr>
      HTML

      footnote_html = footnote ? <<~HTML : ''
        <tr>
          <td style="padding:4px 32px 0; font-size:12.5px; color:#{BRAND[:muted]}; line-height:1.6;">
            #{footnote}
          </td>
        </tr>
      HTML

      mail.html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
      end

      mail.html_part.body = <<~HTML
        <!doctype html>
        <html>
          <body style="margin:0; padding:0; background:#{BRAND[:page_bg]}; font-family:Helvetica,Arial,sans-serif;">
            <span style="display:none; max-height:0; overflow:hidden; opacity:0;">#{preheader}</span>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{BRAND[:page_bg]};">
              <tr>
                <td align="center" style="padding:40px 16px;">
                  <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px; width:100%; background:#{BRAND[:card_bg]}; border-radius:20px; overflow:hidden; border:1px solid #{BRAND[:border]};">
                    <tr>
                      <td align="center" style="padding:36px 32px 24px; border-bottom:1px solid #{BRAND[:border]};">
                        <img src="#{logo_cid}" width="152" alt="REROCK Realty" style="display:block; width:152px; height:auto; border:0;" />
                      </td>
                    </tr>
                    <tr>
                      <td style="padding:32px 32px 8px; font-family:Helvetica,Arial,sans-serif; color:#{BRAND[:ink]}; font-size:15px; line-height:1.65;">
                        #{body_html}
                      </td>
                    </tr>
                    #{cta_html}
                    #{footnote_html}
                    <tr>
                      <td style="padding:28px 32px 32px;">
                        <div style="border-top:1px solid #{BRAND[:border]}; padding-top:20px; font-size:12px; color:#{BRAND[:muted]}; line-height:1.6;">
                          Thank you,<br/>REROCK Realty
                        </div>
                      </td>
                    </tr>
                  </table>
                  <p style="margin:20px 0 0; font-size:11px; color:#{BRAND[:muted]};">REROCK Realty &middot; Where Dreams Meet Strategy</p>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    end

    # A bordered, letter-spaced code block — used for OTP codes and
    # temporary passwords alike so both read as the same "this is the thing
    # you asked for" visual unit.
    def self.code_block(value)
      <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:20px 0;">
          <tr>
            <td align="center" style="background:#{BRAND[:code_bg]}; border:1px solid #{BRAND[:border]}; border-radius:12px; padding:18px 0;">
              <span style="font-family:'Courier New',Courier,monospace; font-size:30px; font-weight:bold; letter-spacing:8px; color:#{BRAND[:primary]};">#{value}</span>
            </td>
          </tr>
        </table>
      HTML
    end
  end
end
