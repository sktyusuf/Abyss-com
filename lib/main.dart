import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:collection';
import 'ad_blocker.dart';
import 'settings_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const TheAbyssApp());
}

class TheAbyssApp extends StatelessWidget {
  const TheAbyssApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Abyss',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1A1A1A),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF16151E),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final GlobalKey webViewKey = GlobalKey();
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  InAppWebViewController? webViewController;
  late PullToRefreshController pullToRefreshController;
  
  double progress = 0;
  bool isLoadError = false;
  bool inChat = false;
  bool _splashVisible = true;
  bool _isDesktopMode = false;
  bool _isReloadingTheme = false; // Prevents white flash by fading out WebView during theme apply
  
  String currentTheme = 'Abyss Black';
  String customThemeUrl = '';
  String localImagePath = '';
  int currentTextZoom = 100;
  
  // Keep track of the last URL globally to prevent navigation drops
  WebUri currentUrl = WebUri('https://thesigmas.blogspot.com/');

  List<Map<String, String>> chatRooms = [];

  final WebUri initialUrl = WebUri('https://thesigmas.blogspot.com/');

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove(); // Safely dismiss the native boot shield
    _loadTheme();
    _fetchChatRooms();

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.transparent,
      ),
      onRefresh: () async {
        // Only allow pull-to-refresh once the splash is fully gone
        if (!_splashVisible && webViewController != null) {
          webViewController!.reload();
        } else {
          pullToRefreshController.endRefreshing();
        }
      },
    );
  }

  // Fetch past chat rooms from Blogger JSON Feed
  Future<void> _fetchChatRooms() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://thesigmas.blogspot.com/feeds/posts/default?alt=json&max-results=500"));
      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();
      final data = json.decode(stringData);
      
      final entries = data['feed']['entry'] as List;
      final List<Map<String, String>> rooms = [];
      
      for (var entry in entries) {
        final title = entry['title']['\$t'] as String;
        final links = entry['link'] as List;
        String? url;
        
        for (var link in links) {
          if (link['rel'] == 'alternate') {
            url = link['href'];
            break;
          }
        }
        
        final lowered = title.toLowerCase();
        // Filter out Chat posts and other specific rooms
        if ((lowered.contains("chat") || lowered.contains("room") || lowered.contains("hall of fame")) && url != null) {
          rooms.add({"title": title, "url": url});
        }
      }
      
      if (mounted) {
        setState(() {
          chatRooms = rooms;
        });
      }
    } catch (e) {
      debugPrint("Error fetching chat rooms: $e");
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    
    String savedUrl = prefs.getString('customThemeUrl') ?? '';
    if (savedUrl.isEmpty) {
      savedUrl = 'https://wallpapersok.com/images/high/moon-phone-varieties-n4a209i7cv27s620.webp';
      await prefs.setString('customThemeUrl', savedUrl);
      await prefs.setString('theme', 'Custom URL');
    }
    
    
    if (mounted) {
      setState(() {
        currentTheme = prefs.getString('theme') ?? 'Abyss Black';
        customThemeUrl = savedUrl;
        localImagePath = prefs.getString('localImagePath') ?? '';
        currentTextZoom = prefs.getInt('textZoom') ?? 100;
      });

      if (webViewController != null) {
        // Hide the webview instantly to show the dark Flutter decoration underneath
        setState(() {
          _isReloadingTheme = true;
        });
        
        await webViewController!.setSettings(settings: _buildWebViewSettings());

        await _injectUserScriptsDynamically(webViewController!);
        webViewController!.reload();
        
        // Safety net: force unhide the WebView after 1.5 seconds regardless of load events.
        // If the user is in Settings, WebView background loading might pause and miss onLoadStop.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && _isReloadingTheme) {
            setState(() {
              _isReloadingTheme = false;
            });
          }
        });
      }
    }
  }

  Future<void> _injectUserScriptsDynamically(InAppWebViewController controller) async {
    await controller.removeAllUserScripts();

    final String backgroundStripCSS = currentTheme == 'Abyss Black'
        ? ''
        : '''
            body, html, .bg-photo, .body-fauxcolumn-outer, #page-wrapper, .content-outer, .content-inner, .sect-auth-outer {
                background: transparent !important;
                background-color: transparent !important;
                background-image: none !important;
            }
            body > * { background-color: transparent !important; }
        ''';

    if (backgroundStripCSS.isNotEmpty) {
      await controller.addUserScript(userScript: UserScript(
        source: '''
            var bgStyle = document.createElement('style');
            bgStyle.id = 'flutter-theme-override';
            bgStyle.type = 'text/css';
            bgStyle.innerHTML = `$backgroundStripCSS`;
            document.documentElement.appendChild(bgStyle);
        ''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }

  }

  BoxDecoration _buildBackgroundDecoration() {
    if (currentTheme == 'Glassmorphism') {
      return const BoxDecoration(
        color: Colors.black,
        image: DecorationImage(
          image: AssetImage('assets/themes/glass_theme.png'),
          fit: BoxFit.cover,
        ),
      );
    } else if (currentTheme == 'Midnight Purple') {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E004F), Colors.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    } else if (currentTheme == 'Deep Ocean') {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00152F), Color(0xFF000712)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      );
    } else if (currentTheme == 'Custom URL' && customThemeUrl.isNotEmpty) {
      return BoxDecoration(
        color: Colors.black,
        image: DecorationImage(
          image: NetworkImage(customThemeUrl),
          fit: BoxFit.cover,
        ),
      );
    } else if (currentTheme == 'Local Image' && localImagePath.isNotEmpty) {
      final file = File(localImagePath);
      if (file.existsSync()) {
        return BoxDecoration(
          color: Colors.black,
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return const BoxDecoration(color: Colors.black);
  }

  Future<void> _toggleDesktopMode() async {
    if (webViewController == null) return;
    setState(() {
      _isDesktopMode = !_isDesktopMode;
      _splashVisible = true; // Show loading splash when switching layout
    });
    
    await webViewController!.setSettings(settings: _buildWebViewSettings());
    webViewController!.reload();
  }

  InAppWebViewSettings _buildWebViewSettings() {
    const desktopUA =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    const mobileUA =
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

    return InAppWebViewSettings(
      textZoom: _isDesktopMode ? 60 : currentTextZoom,
      disableHorizontalScroll: true,
      verticalScrollBarEnabled: false,
      overScrollMode: OverScrollMode.NEVER,
      transparentBackground: true, // Crucial for overlaying custom theme
      javaScriptEnabled: true,
      cacheEnabled: true, // Enable powerful aggressive caching
      hardwareAcceleration: true, // Force Android to use GPU for Chromium
      databaseEnabled: true,
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: true,
      contentBlockers: AdBlocker.contentBlockers,
      supportMultipleWindows: true, // For Disqus login popups
      javaScriptCanOpenWindowsAutomatically: true,
      thirdPartyCookiesEnabled: true, // Needed for Disqus
      domStorageEnabled: true,
      allowsInlineMediaPlayback: true,
      userAgent: _isDesktopMode ? desktopUA : "", // Empty allows system to resolve true mobile UA naturally
      preferredContentMode: _isDesktopMode
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.RECOMMENDED,
      useWideViewPort: true, // MUST remain true or HTML <meta viewport> tags break severely
      loadWithOverviewMode: true, // MUST remain true or horizontal layouts overflow screen
    );
  }

  Future<bool> _goBack() async {
    if (scaffoldKey.currentState?.isDrawerOpen == true) {
      // Close drawer first if it's open
      Navigator.pop(context);
      return false; 
    }
    if (webViewController != null) {
      if (await webViewController!.canGoBack()) {
        webViewController!.goBack();
        return false; // Prevent default pop
      }
    }
    return true; // Allow default pop (close app)
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _goBack();
        if (shouldPop) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        key: scaffoldKey,
        drawer: Drawer(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
                color: const Color(0xFF100F17),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline, color: Colors.purpleAccent, size: 32),
                    SizedBox(height: 12),
                    Text(
                      'Past Chatrooms', 
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 22, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Archive of all your chats',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    )
                  ],
                ),
              ),
              if (chatRooms.isEmpty)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.purpleAccent),
                  ),
                ),
              if (chatRooms.isNotEmpty)
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: chatRooms.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final room = chatRooms[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        title: Text(
                          room['title']!,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.pop(context); // Close the drawer
                          if (webViewController != null) {
                            webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(room['url']!)));
                          }
                        },
                      );
                    },
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white70),
                title: const Text('Settings', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(onThemeChanged: _loadTheme),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        body: Container(
          decoration: _buildBackgroundDecoration(),
          child: SafeArea(
            child: Stack(
              children: [
              // Wrap the WebView in an opacity fader to eliminate white flashes
              AnimatedOpacity(
                opacity: _isReloadingTheme ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: RepaintBoundary(
                  child: InAppWebView(
                    key: webViewKey,
                  initialUrlRequest: URLRequest(url: initialUrl),
                  pullToRefreshController: pullToRefreshController,
                  initialUserScripts: UnmodifiableListView<UserScript>([]),
                  initialSettings: _buildWebViewSettings(),
                  onWebViewCreated: (controller) async {
                  webViewController = controller;
                  await _injectUserScriptsDynamically(controller);
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    progress = 0;
                    isLoadError = false;
                    // _splashVisible is intentionally NOT reset here.
                    // _isReloadingTheme ensures we only hide the white flash.
                  });
                },
                onLoadStop: (controller, url) async {
                  pullToRefreshController.endRefreshing();
                  setState(() {
                    progress = 1.0;
                  });
                  // Wait briefly for CSS injections to paint before dropping cover
                  await Future.delayed(const Duration(milliseconds: 400));
                  if (mounted) {
                    setState(() {
                      _splashVisible = false;
                      _isReloadingTheme = false; // Reveal the webview securely
                    });
                  }
                },
                onUpdateVisitedHistory: (controller, url, androidIsReload) {
                  if (url != null) {
                    currentUrl = url;
                    setState(() {
                      final lowered = url.toString().toLowerCase();
                      inChat = lowered.contains('chat');
                    });
                  }
                },
                onProgressChanged: (controller, progress) {
                  if (progress == 100) {
                    pullToRefreshController.endRefreshing();
                  }
                  setState(() {
                    this.progress = progress / 100;
                  });
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == false) return;
                  pullToRefreshController.endRefreshing();
                  setState(() {
                    isLoadError = true;
                    _isReloadingTheme = false; // Safety net for errors
                  });
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  var uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.CANCEL;

                  if (!["http", "https", "file", "chrome", "data", "javascript", "about"].contains(uri.scheme)) {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                      return NavigationActionPolicy.CANCEL;
                    }
                  }

                  if (uri.scheme == 'http' || uri.scheme == 'https') {
                    final host = uri.host.toLowerCase();
                    // Let the app handle its own domain and disqus for login
                    if (host.contains('thesigmas.blogspot.com') ||
                        host.contains('disqus.com') ||
                        host.contains('google.com') ||
                        host.contains('accounts.google.com') ||
                        host.contains('twitter.com') ||
                        host.contains('facebook.com')) {
                      return NavigationActionPolicy.ALLOW;
                    } else {
                      // Everything else opens in external browser
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      return NavigationActionPolicy.CANCEL;
                    }
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCreateWindow: (controller, createWindowAction) async {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: EdgeInsets.zero,
                        child: SafeArea(
                          child: Column(
                            children: [
                              AppBar(
                                title: const Text('Login'),
                                backgroundColor: const Color(0xFF1A1A1A),
                                leading: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                              Expanded(
                                child: InAppWebView(
                                  windowId: createWindowAction.windowId,
                                  initialSettings: InAppWebViewSettings(
                                    javaScriptEnabled: true,
                                    thirdPartyCookiesEnabled: true,
                                    domStorageEnabled: true,
                                  ),
                                  onCloseWindow: (controller) {
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                  return true;
                },
              ),
              ),
              ),

              // GIF Overlay with smooth fade-out when page fully loads
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _splashVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: IgnorePointer(
                    ignoring: !_splashVisible,
                    child: Image.asset(
                      'assets/abyss.gif',
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(color: const Color(0xFF16151E));
                      },
                    ),
                  ),
                ),
              ),
              
              // Top-Left Navigation Menu Button (only in chat)
              if (inChat)
                Positioned(
                  top: 16,
                  left: 16,
                  child: FloatingActionButton(
                    mini: true,
                    elevation: 4,
                    backgroundColor: const Color(0xFF282436).withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.menu),
                    onPressed: () {
                      scaffoldKey.currentState?.openDrawer();
                    },
                  ),
                ),

              // Desktop Mode toggle — always visible top-right
              Positioned(
                top: 12,
                right: 12,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: _isDesktopMode
                        ? Colors.purpleAccent.withValues(alpha: 0.85)
                        : const Color(0xFF282436).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _toggleDesktopMode,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isDesktopMode ? Icons.desktop_windows : Icons.phone_android,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isDesktopMode ? 'Desktop' : 'Mobile',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (progress < 1.0)
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  color: Colors.purpleAccent,
                ),
              if (isLoadError)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        const Text('Failed to load page. Please check your connection.', 
                            style: TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white, 
                            side: const BorderSide(color: Colors.purpleAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)
                          ),
                          onPressed: () {
                            if (webViewController != null) {
                              webViewController!.reload();
                            }
                            setState(() {
                              isLoadError = false;
                            });
                          },
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
