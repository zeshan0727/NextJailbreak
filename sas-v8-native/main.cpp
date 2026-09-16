#include "pch.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using namespace Microsoft::UI::Xaml::Controls;
using namespace Microsoft::UI::Xaml::Media;
using namespace Microsoft::UI::Xaml::XamlTypeInfo;
using namespace Microsoft::UI::Xaml::Markup;
using namespace Windows::UI::Xaml::Interop;
using namespace Windows::Foundation;
using namespace Windows::UI;

namespace sas
{
    SolidColorBrush Brush(byte a, byte r, byte g, byte b)
    {
        return SolidColorBrush(Color{a, r, g, b});
    }

    Border Card(IInspectable const& content, Thickness margin = Thickness{0,0,0,14})
    {
        Border b;
        b.CornerRadius(CornerRadius{18});
        b.Padding(Thickness{20});
        b.Margin(margin);
        b.BorderThickness(Thickness{1});
        b.BorderBrush(Brush(55, 255, 255, 255));
        b.Background(Brush(150, 23, 27, 38));
        b.Child(content.as<UIElement>());
        return b;
    }

    TextBlock Label(hstring const& text, double size = 14, FontWeight weight = Windows::UI::Text::FontWeights::Normal())
    {
        TextBlock t;
        t.Text(text);
        t.FontSize(size);
        t.FontWeight(weight);
        t.Foreground(Brush(255, 235, 238, 245));
        return t;
    }
}

class MainWindow : public WindowT<MainWindow>
{
public:
    MainWindow()
    {
        Title(L"Story Automation Studio 8.0");
        BuildShell();
        ShowDirector();
    }

private:
    Grid m_root{nullptr};
    ContentControl m_content{nullptr};
    TextBlock m_status{nullptr};
    TextBox m_brief{nullptr};
    NumberBox m_duration{nullptr};

    void BuildShell()
    {
        m_root = Grid();
        m_root.Background(sas::Brush(255, 10, 13, 20));
        m_root.RequestedTheme(ElementTheme::Dark);

        ColumnDefinition sidebarCol;
        sidebarCol.Width(GridLengthHelper::FromPixels(238));
        ColumnDefinition contentCol;
        contentCol.Width(GridLengthHelper::FromValueAndType(1, GridUnitType::Star));
        m_root.ColumnDefinitions().Append(sidebarCol);
        m_root.ColumnDefinitions().Append(contentCol);

        auto sidebar = StackPanel();
        sidebar.Padding(Thickness{18,24,18,18});
        sidebar.Background(sas::Brush(255, 15, 18, 28));
        Grid::SetColumn(sidebar, 0);

        auto brand = sas::Label(L"STORY AUTOMATION", 12, Windows::UI::Text::FontWeights::SemiBold());
        brand.Foreground(sas::Brush(255, 136, 171, 255));
        brand.Margin(Thickness{8,0,0,4});
        sidebar.Children().Append(brand);
        auto title = sas::Label(L"Studio 8", 30, Windows::UI::Text::FontWeights::Bold());
        title.Margin(Thickness{8,0,0,28});
        sidebar.Children().Append(title);

        auto addNav = [&](hstring const& text, auto handler)
        {
            Button b;
            b.Content(box_value(text));
            b.HorizontalAlignment(HorizontalAlignment::Stretch);
            b.HorizontalContentAlignment(HorizontalAlignment::Left);
            b.Padding(Thickness{16,12,16,12});
            b.Margin(Thickness{0,0,0,8});
            b.CornerRadius(CornerRadius{12});
            b.Click(handler);
            sidebar.Children().Append(b);
        };

        addNav(L"AI Director", [this](IInspectable const&, RoutedEventArgs const&) { ShowDirector(); });
        addNav(L"Production", [this](IInspectable const&, RoutedEventArgs const&) { ShowProduction(); });
        addNav(L"Studio Tools", [this](IInspectable const&, RoutedEventArgs const&) { ShowTools(); });
        addNav(L"Settings", [this](IInspectable const&, RoutedEventArgs const&) { ShowSettings(); });

        auto footer = sas::Label(L"NATIVE C++ / WINUI 3\nCore + AI Director milestone", 11);
        footer.Opacity(0.58);
        footer.Margin(Thickness{8,34,0,0});
        sidebar.Children().Append(footer);

        m_content = ContentControl();
        m_content.Margin(Thickness{28,24,28,24});
        Grid::SetColumn(m_content, 1);

        m_root.Children().Append(sidebar);
        m_root.Children().Append(m_content);
        Content(m_root);
    }

    StackPanel PageHeader(hstring const& titleText, hstring const& subText)
    {
        StackPanel header;
        auto eyebrow = sas::Label(L"STORY AUTOMATION STUDIO 8.0", 11, Windows::UI::Text::FontWeights::SemiBold());
        eyebrow.Foreground(sas::Brush(255, 125, 168, 255));
        header.Children().Append(eyebrow);
        auto title = sas::Label(titleText, 34, Windows::UI::Text::FontWeights::Bold());
        title.Margin(Thickness{0,5,0,4});
        header.Children().Append(title);
        auto sub = sas::Label(subText, 14);
        sub.Opacity(0.65);
        sub.Margin(Thickness{0,0,0,22});
        header.Children().Append(sub);
        return header;
    }

    void ShowDirector()
    {
        auto scroll = ScrollViewer();
        auto page = StackPanel();
        page.MaxWidth(1120);
        page.HorizontalAlignment(HorizontalAlignment::Stretch);
        page.Children().Append(PageHeader(L"AI Director", L"Astra plans. Your RTX 3090 renders locally."));

        StackPanel briefCard;
        briefCard.Children().Append(sas::Label(L"VIDEO BRIEF", 12, Windows::UI::Text::FontWeights::SemiBold()));
        m_brief = TextBox();
        m_brief.AcceptsReturn(true);
        m_brief.TextWrapping(TextWrapping::Wrap);
        m_brief.MinHeight(170);
        m_brief.PlaceholderText(L"Describe the story or generate a researched trending idea...");
        m_brief.Margin(Thickness{0,10,0,14});
        briefCard.Children().Append(m_brief);

        auto actionRow = StackPanel();
        actionRow.Orientation(Orientation::Horizontal);
        actionRow.Spacing(10);
        Button trend;
        trend.Content(box_value(L"Generate Trending Prompt"));
        trend.Padding(Thickness{18,10,18,10});
        trend.Click([this](IInspectable const&, RoutedEventArgs const&) {
            m_brief.Text(L"Create a researched, high-retention human short-form story. Hook in the first 2 seconds, maintain strong visual continuity, use realistic humans, a clear emotional turn, and a resolved ending. Astra research integration is connected in the next runtime milestone.");
            SetStatus(L"Trending prompt template prepared. Live Astra research runtime is the next v8 milestone.", false);
        });
        actionRow.Children().Append(trend);
        Button clear;
        clear.Content(box_value(L"Clear"));
        clear.Click([this](IInspectable const&, RoutedEventArgs const&) { m_brief.Text(L""); });
        actionRow.Children().Append(clear);
        briefCard.Children().Append(actionRow);
        page.Children().Append(sas::Card(briefCard));

        StackPanel options;
        options.Children().Append(sas::Label(L"PRODUCTION", 12, Windows::UI::Text::FontWeights::SemiBold()));
        auto controls = StackPanel();
        controls.Orientation(Orientation::Horizontal);
        controls.Spacing(16);
        controls.Margin(Thickness{0,12,0,12});

        StackPanel durCol;
        durCol.Width(160);
        durCol.Children().Append(sas::Label(L"Duration (seconds)", 12));
        m_duration = NumberBox();
        m_duration.Value(30);
        m_duration.Minimum(5);
        m_duration.Maximum(300);
        durCol.Children().Append(m_duration);
        controls.Children().Append(durCol);

        ToggleSwitch narration;
        narration.Header(box_value(L"Narration"));
        narration.IsOn(true);
        controls.Children().Append(narration);
        ToggleSwitch music;
        music.Header(box_value(L"Music"));
        music.IsOn(true);
        controls.Children().Append(music);
        ToggleSwitch maintain;
        maintain.Header(box_value(L"Story Maintain"));
        maintain.IsOn(true);
        controls.Children().Append(maintain);
        ToggleSwitch realism;
        realism.Header(box_value(L"Photorealism Lock"));
        realism.IsOn(true);
        controls.Children().Append(realism);
        options.Children().Append(controls);

        Button generate;
        generate.Content(box_value(L"Start Complete Production"));
        generate.HorizontalAlignment(HorizontalAlignment::Left);
        generate.Padding(Thickness{24,12,24,12});
        generate.Click([this](IInspectable const&, RoutedEventArgs const&) {
            SetStatus(L"v8 native shell is ready. Local ComfyUI/LTX generation runtime is being ported next; use v7.2.1 for production until that milestone is installed.", true);
        });
        options.Children().Append(generate);
        page.Children().Append(sas::Card(options));

        StackPanel engine;
        engine.Children().Append(sas::Label(L"ENGINE ROUTING", 12, Windows::UI::Text::FontWeights::SemiBold()));
        auto route = sas::Label(L"1 Main  →  Flux / USO\n2–3 Mains  →  Qwen-Image-Edit-2511\n4+ Mains  →  Block and split scene\nReal-human references  →  hard photorealism lock", 14);
        route.Margin(Thickness{0,12,0,0});
        route.LineHeight(24);
        engine.Children().Append(route);
        page.Children().Append(sas::Card(engine));

        m_status = sas::Label(L"Native core ready", 13, Windows::UI::Text::FontWeights::SemiBold());
        m_status.Foreground(sas::Brush(255, 126, 225, 166));
        m_status.Margin(Thickness{4,6,0,24});
        page.Children().Append(m_status);
        scroll.Content(page);
        m_content.Content(scroll);
    }

    void ShowProduction()
    {
        auto page = StackPanel();
        page.MaxWidth(1120);
        page.Children().Append(PageHeader(L"Production", L"Scene timeline, recovery state and local GPU activity."));
        StackPanel body;
        body.Children().Append(sas::Label(L"Production timeline", 20, Windows::UI::Text::FontWeights::SemiBold()));
        auto t = sas::Label(L"Native project state / checkpoint timeline will appear here.\nCompleted assets will be reused instead of regenerated.", 14);
        t.Margin(Thickness{0,10,0,0}); t.Opacity(0.72);
        body.Children().Append(t);
        page.Children().Append(sas::Card(body));
        m_content.Content(page);
    }

    void ShowTools()
    {
        auto page = StackPanel();
        page.MaxWidth(1120);
        page.Children().Append(PageHeader(L"Studio Tools", L"Advanced manual tools stay available without cluttering navigation."));
        StackPanel body;
        body.Children().Append(sas::Label(L"Local engines", 20, Windows::UI::Text::FontWeights::SemiBold()));
        auto t = sas::Label(L"Image Studio  •  Video Studio  •  Narration  •  Music  •  Final Render  •  Social Pack", 14);
        t.Margin(Thickness{0,10,0,0}); t.Opacity(0.75);
        body.Children().Append(t);
        page.Children().Append(sas::Card(body));
        m_content.Content(page);
    }

    void ShowSettings()
    {
        auto scroll = ScrollViewer();
        auto page = StackPanel();
        page.MaxWidth(1120);
        page.Children().Append(PageHeader(L"Settings", L"Connections, local engines and application appearance."));

        StackPanel conn;
        conn.Children().Append(sas::Label(L"CONNECTIONS", 12, Windows::UI::Text::FontWeights::SemiBold()));
        PasswordBox api;
        api.PlaceholderText(L"OpenAI API key");
        api.Margin(Thickness{0,12,0,8});
        conn.Children().Append(api);
        TextBox agent;
        agent.Header(box_value(L"Agent ID"));
        agent.Text(L"agent_267092bfb5534f83abf863b47d89a7f6ebee9bb27f4b44c48b");
        agent.Margin(Thickness{0,6,0,8});
        conn.Children().Append(agent);
        TextBox comfy;
        comfy.Header(box_value(L"ComfyUI"));
        comfy.Text(L"http://127.0.0.1:8188");
        conn.Children().Append(comfy);
        Button save;
        save.Content(box_value(L"Save Settings"));
        save.Margin(Thickness{0,16,0,0});
        save.HorizontalAlignment(HorizontalAlignment::Left);
        save.Click([this](IInspectable const&, RoutedEventArgs const&) { SetStatus(L"Settings UI ready. DPAPI persistence is part of the next services-port milestone.", false); });
        conn.Children().Append(save);
        page.Children().Append(sas::Card(conn));

        StackPanel appearance;
        appearance.Children().Append(sas::Label(L"APPEARANCE", 12, Windows::UI::Text::FontWeights::SemiBold()));
        auto desc = sas::Label(L"Native dark glass foundation. Acrylic / translucent theme variants will be added on top of this shell.", 14);
        desc.Margin(Thickness{0,10,0,0}); desc.Opacity(0.72);
        appearance.Children().Append(desc);
        page.Children().Append(sas::Card(appearance));

        scroll.Content(page);
        m_content.Content(scroll);
    }

    void SetStatus(hstring const& text, bool warning)
    {
        if (m_status)
        {
            m_status.Text(text);
            m_status.Foreground(warning ? sas::Brush(255, 255, 190, 95) : sas::Brush(255, 126, 225, 166));
        }
    }
};

class App : public ApplicationT<App, IXamlMetadataProvider>
{
public:
    void OnLaunched(LaunchActivatedEventArgs const&)
    {
        Resources().MergedDictionaries().Append(XamlControlsResources());
        window = make<MainWindow>();
        window.Activate();
    }
    IXamlType GetXamlType(TypeName const& type) { return provider.GetXamlType(type); }
    IXamlType GetXamlType(hstring const& fullname) { return provider.GetXamlType(fullname); }
    com_array<XmlnsDefinition> GetXmlnsDefinitions() { return provider.GetXmlnsDefinitions(); }
private:
    Window window{nullptr};
    XamlControlsXamlMetaDataProvider provider;
};

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int)
{
    init_apartment();
    Application::Start([](auto&&) { make<App>(); });
    return 0;
}
