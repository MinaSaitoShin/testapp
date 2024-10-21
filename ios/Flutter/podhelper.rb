# This is the podhelper.rb file required for integrating Flutter with iOS
flutter_application_path = File.expand_path('..', __dir__)

load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')
