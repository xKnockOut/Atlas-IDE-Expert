unit Shell.Monitor.ReportPage;

// Host-Rolle Shell von AtlasMonitor (#1900): Reiter „Bericht“ mit eingebettetem Browser (TEdgeBrowser, WebView2) für
// die interaktiven HTML-Seiten von Architektur und Hotspots. Der Reiter erscheint erst mit der ersten Seite. Fehlt
// WebView2 (Laufzeit oder WebView2Loader.dll), öffnet sich die Seite einmal mit Hinweis im Standardbrowser. Die Daten
// des Browsers liegen unter %LOCALAPPDATA%\Atlas\WebView2, weil der Programmordner schreibgeschützt sein kann.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Edge;

type
  TMonitorReportPage = class(TComponent)
  private
    FPages: TPageControl;
    FTab: TTabSheet;
    FBrowser: TEdgeBrowser;
    FFileName: string;
    FFailed: Boolean;
    FOnInform: TProc<string>;
    procedure BrowserCreated(ASender: TCustomEdgeBrowser; AResult: HResult);
    procedure OpenOutside;
  public
    /// <summary>Legt den (noch unsichtbaren) Reiter in APages an; AOnInform zeigt Hinweise.</summary>
    constructor Create(AOwner: TComponent; APages: TPageControl; const AOnInform: TProc<string>); reintroduce;
    /// <summary>Zeigt AFileName (HTML) im Reiter und wechselt dorthin; ohne WebView2 im Standardbrowser.</summary>
    procedure ShowFile(const AFileName: string);
  end;

implementation

uses
  System.IOUtils,
  Atlas.Text.Uris,
  Atlas.Common.Monitor.Texts,
  Atlas.Windows.Monitor.Adapters.System;

constructor TMonitorReportPage.Create(AOwner: TComponent; APages: TPageControl; const AOnInform: TProc<string>);
begin
  inherited Create(AOwner);
  FPages := APages;
  FOnInform := AOnInform;
  FTab := TTabSheet.Create(Self);
  FTab.Caption := TMonitorTexts.Text(TMonitorText.TabReport);
  // Ohne Fenster scheitert ein sichtbarer Reiter; ShowFile zeigt ihn.
  FTab.TabVisible := False;
  FTab.PageControl := FPages;
  FBrowser := TEdgeBrowser.Create(Self);
  FBrowser.Align := alClient;
  FBrowser.UserDataFolder := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'WebView2');
  FBrowser.OnCreateWebViewCompleted := BrowserCreated;
  FBrowser.Parent := FTab;
end;

procedure TMonitorReportPage.OpenOutside;
begin
  TMonitorSystem.OpenFile(FFileName);
end;

procedure TMonitorReportPage.BrowserCreated(ASender: TCustomEdgeBrowser; AResult: HResult);
begin
  if Succeeded(AResult) then
  begin
    Exit;
  end;
  FFailed := True;
  FTab.TabVisible := False;
  if Assigned(FOnInform) then
  begin
    FOnInform(TMonitorTexts.Text(TMonitorText.BrowserFailed));
  end;
  OpenOutside;
end;

procedure TMonitorReportPage.ShowFile(const AFileName: string);
begin
  FFileName := AFileName;
  if FFailed then
  begin
    OpenOutside;
    Exit;
  end;
  FTab.TabVisible := True;
  FPages.ActivePage := FTab;
  FBrowser.Navigate(TTextUris.FromPath(AFileName));
end;

end.
