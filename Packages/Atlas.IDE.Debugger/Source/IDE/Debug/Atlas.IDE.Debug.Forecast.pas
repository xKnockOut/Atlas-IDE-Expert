unit Atlas.IDE.Debug.Forecast;

// Bedingungen vorausschauen (#2169) in der IDE, Teil von „Warum bin ich hier?“
// (Atlas.IDE.Debug.WhyHere, das Halt, Anfrage und Auswertung übernimmt):
//   - Anfrage atlas.server.upcomingConditions mit debug.predictConditions.lines.
//   - Hinweis je Kopfzeile („⟨= False · FOnline⟩“, „⟨→ smManual⟩“) und blasse
//     Zeilen der übersprungenen Zweige (debug.predictConditions.dimSkipped):
//     Hintergrundfarbe halb durchsichtig über die Zeile, der Text bleibt lesbar.
//   - Klick auf einen Hinweis: Menü „Vorhersage für diese Sitzung aus“; bis zum
//     Ende der Sitzung keine Anfrage und keine Anzeige.
// Nur im Hauptthread verwenden.

interface

uses
  System.Types,
  Vcl.Menus,
  ToolsAPI.Editor,
  Atlas.Core.Debug.Forecast;

type
  TAtlasIdeDebugForecast = class
  private
    FForecast: TAtlasForecast;
    /// <summary>Für diese Sitzung abgeschaltet (Menü am Hinweis).</summary>
    FOff: Boolean;
    FMenu: TPopupMenu;
    procedure OffClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>debug.predictConditions an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Argumente der Anfrage: [uri, line, debug.predictConditions.lines].</summary>
    class function Arguments(const AUri: string; ALine: Integer): string; static;
    /// <summary>Anfrage stellen? An und nicht für diese Sitzung abgeschaltet.</summary>
    function Wanted: Boolean;
    /// <summary>Antwort übernehmen; False ohne Bedingungen.</summary>
    function Accept(const AFileName, AAnswer: string): Boolean;
    /// <summary>Neue bzw. beendete Sitzung: Abschalten zurücknehmen, alles verwerfen.</summary>
    procedure SessionChanged;
    procedure Clear;
    /// <summary>Hinweis am Ende der Zeile ALine (ab 0); '' ohne.</summary>
    function LineText(const AFileName: string; ALine: Integer): string;
    /// <summary>Zeile blass zeichnen, wenn sie nur in übersprungenen Zweigen liegt.</summary>
    procedure PaintDimmed(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
    /// <summary>Menü am Hinweis an APoint (Bildschirm).</summary>
    procedure ShowMenu(const APoint: TPoint);
    property Model: TAtlasForecast read FForecast;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.Debug.WhyHere,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Deckkraft der Hintergrundfarbe über übersprungenen Zweigen.</summary>
  cDimAlpha = 150;

function ForecastTexts: TAtlasForecastTexts;
begin
  Result := Default(TAtlasForecastTexts);
  Result.ElseBranch := TAtlasDebugStrings.Text(TAtlasDebugTextId.WhyHereElseBranch);
  Result.NoBranch := TAtlasDebugStrings.Text(TAtlasDebugTextId.PredictNoBranch);
end;

{ TAtlasIdeDebugForecast }

constructor TAtlasIdeDebugForecast.Create;
begin
  inherited Create;
  FForecast := TAtlasForecast.Create;
end;

destructor TAtlasIdeDebugForecast.Destroy;
begin
  FreeAndNil(FMenu);
  FreeAndNil(FForecast);
  inherited Destroy;
end;

class function TAtlasIdeDebugForecast.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugPredictConditions;
end;

class function TAtlasIdeDebugForecast.Arguments(const AUri: string; ALine: Integer): string;
begin
  Result := TAtlasForecast.Arguments(AUri, ALine, TAtlasIdeSettings.Current.DebugPredictLines);
end;

function TAtlasIdeDebugForecast.Wanted: Boolean;
begin
  Result := Enabled and not FOff;
end;

function TAtlasIdeDebugForecast.Accept(const AFileName, AAnswer: string): Boolean;
var
  mBlocks: TAtlasWhyHereBlocks;
  mBranches: TArray<TAtlasForecastBranches>;
begin
  Result := Wanted and TAtlasForecast.ReadAnswerText(AAnswer, mBlocks, mBranches) and (Length(mBlocks) > 0);
  if Result then
  begin
    FForecast.Start(AFileName, mBlocks, mBranches);
  end;
end;

procedure TAtlasIdeDebugForecast.SessionChanged;
begin
  FOff := False;
  Clear;
end;

procedure TAtlasIdeDebugForecast.Clear;
begin
  FForecast.Clear;
end;

function TAtlasIdeDebugForecast.LineText(const AFileName: string; ALine: Integer): string;
begin
  Result := FForecast.LineText(AFileName, ALine, ForecastTexts);
end;

procedure TAtlasIdeDebugForecast.PaintDimmed(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
var
  mBack: COLORREF;
begin
  // Erst die Zeile (billig ohne Vorhersage), dann die Einstellung.
  if not FForecast.Dimmed(AContext.FileName, AContext.LogicalLineNum - 1) or
    not TAtlasIdeSettings.Current.DebugPredictDimSkipped then
  begin
    Exit;
  end;
  mBack := COLORREF(TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Right - 2, ARect.Top + 1));
  TAtlasIdeStyle.Blend(AContext.Canvas.Handle, ARect, mBack, cDimAlpha);
end;

procedure TAtlasIdeDebugForecast.ShowMenu(const APoint: TPoint);
var
  mItem: TMenuItem;
begin
  if not FForecast.Active then
  begin
    Exit;
  end;
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.PredictOffForSession);
    mItem.OnClick := OffClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDebugForecast.OffClick(Sender: TObject);
begin
  FOff := True;
  Clear;
  TAtlasDebugLineEnd.Invalidate;
end;

end.
