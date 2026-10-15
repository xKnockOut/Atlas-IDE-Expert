unit Atlas.UI.Welcome.Header;

// Kopf der Atlas-Willkommensseite (#753): links das Atlas-Symbol G1a (#751,
// Variante nach dem Hintergrund, bei jedem Zeichnen neu bestimmt, damit ein
// Themenwechsel ohne Neustart wirkt), daneben die Grußzeile („Guten Abend,
// Marco“) und darunter Version und Kurzstatus („Atlas 1.0.0 · Server läuft ·
// 1.284 Units im Index“). Rechts steht das Suchfeld (#760, ShowSearch;
// welcomePage.search). Ohne Grußzeile (welcomePage.greeting aus) steht
// „Atlas“ dort.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Greeting,
  Atlas.UI.Style.Symbol,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Search;

type
  /// <summary>Was der Kopf zeigt; die IDE-Schicht füllt es.</summary>
  TAtlasWelcomeHeaderInfo = record
    Greeting: Boolean;
    Hour: Integer;
    FirstName: string;
    Version: string;
    Phase: TAtlasServerPhase;
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    Units: Integer;
    Indexing: Boolean;
    Percent: Integer;
  end;

  TAtlasWelcomeHeaderFrame = class(TAtlasWelcomeFrame)
  public const
    HeaderHeight = 64;
    SymbolSize = 40;
    SearchWidth = 320;
    /// <summary>Höhe der Suchzeile unter dem Gruß, wenn das Feld daneben keinen Platz hat.</summary>
    SearchRowHeight = 36;
  private
    FSymbol: TAtlasSymbolImage;
    FGreeting: TLabel;
    FInfo: TLabel;
    FSearchHost: TPanel;
    FSearch: TAtlasWelcomeSearchBox;
    FData: TAtlasWelcomeHeaderInfo;
    FArranging: Boolean;
    procedure Arrange;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowInfo(const AInfo: TAtlasWelcomeHeaderInfo);
    /// <summary>Suchfeld zeigen (beim ersten Mal anlegen) bzw. ausblenden und leeren (#760).</summary>
    procedure ShowSearch(AVisible: Boolean);
    /// <summary>„Guten Abend, Marco“; ohne Namen nur der Gruß.</summary>
    class function GreetingText(AHour: Integer; const AFirstName: string): string; static;
    /// <summary>„Server läuft · 1.284 Units im Index“ in der Sprache der IDE.</summary>
    class function StatusText(APhase: TAtlasServerPhase; AUnits: Integer; AIndexing: Boolean;
      APercent: Integer): string; static;
    /// <summary>„Atlas 1.0.0 · “ plus StatusText.</summary>
    class function InfoText(const AInfo: TAtlasWelcomeHeaderInfo): string; static;
    /// <summary>Zahl mit Tausendertrennzeichen der Sprache (1.284 bzw. 1,284).</summary>
    class function Thousands(AValue: Integer): string; static;
    property Symbol: TAtlasSymbolImage read FSymbol;
    property GreetingLabel: TLabel read FGreeting;
    property InfoLabel: TLabel read FInfo;
    /// <summary>Platz rechts im Kopf für das Suchfeld (#760).</summary>
    property SearchHost: TPanel read FSearchHost;
    /// <summary>Suchfeld; nil, bis ShowSearch(True) es anlegt.</summary>
    property Search: TAtlasWelcomeSearchBox read FSearch;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Strings;

{ TAtlasWelcomeHeaderFrame }

constructor TAtlasWelcomeHeaderFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := HeaderHeight;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Self;
  FSymbol.LogicalSize := SymbolSize;
  FSymbol.Left := 8;
  FSymbol.Top := (HeaderHeight - SymbolSize) div 2;
  FGreeting := TLabel.Create(Self);
  FGreeting.Parent := Self;
  FGreeting.Left := SymbolSize + 20;
  FGreeting.Top := 10;
  FGreeting.Font.Size := 14;
  FGreeting.Font.Style := [fsBold];
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.Left := FGreeting.Left;
  FInfo.Top := 38;
  FInfo.Font.Color := clGrayText;
  FSearchHost := TPanel.Create(Self);
  FSearchHost.Parent := Self;
  FSearchHost.Align := alRight;
  FSearchHost.AlignWithMargins := True;
  FSearchHost.Margins.SetBounds(8, 19, 12, 19);
  FSearchHost.Width := 0;
  FSearchHost.BevelOuter := bvNone;
  FSearchHost.ParentBackground := True;
  FData.Phase := TAtlasServerPhase.NotStarted;
  FData.Units := -1;
  FData.Percent := -1;
  FData.Greeting := True;
  FData.Hour := 12;
end;

procedure TAtlasWelcomeHeaderFrame.ShowInfo(const AInfo: TAtlasWelcomeHeaderInfo);
begin
  FData := AInfo;
  if AInfo.Greeting then
    FGreeting.Caption := GreetingText(AInfo.Hour, AInfo.FirstName)
  else
    FGreeting.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeHeaderTitle);
  FInfo.Caption := InfoText(AInfo);
  Arrange;
  // Symbol neu zeichnen: Die Variante folgt dem Hintergrund (Themenwechsel).
  FSymbol.Invalidate;
end;

procedure TAtlasWelcomeHeaderFrame.ShowSearch(AVisible: Boolean);
begin
  if AVisible and (FSearch = nil) then
  begin
    FSearch := TAtlasWelcomeSearchBox.Create(Self);
    FSearch.Parent := FSearchHost;
    FSearch.Align := alClient;
  end;
  if FSearch <> nil then
  begin
    if not AVisible then
      FSearch.Clear;
    FSearch.Visible := AVisible;
  end;
  if AVisible then
    FSearchHost.Width := ScaleValue(SearchWidth)
  else
    FSearchHost.Width := 0;
  Arrange;
end;

procedure TAtlasWelcomeHeaderFrame.Resize;
begin
  inherited;
  Arrange;
end;

procedure TAtlasWelcomeHeaderFrame.Arrange;
var
  TextRight: Integer;
  Below: Boolean;
begin
  // Reicht die Breite nicht für Gruß und Suchfeld nebeneinander, steht das Feld in einer
  // eigenen Zeile darunter (schmales Fenster „Atlas-Start“).
  // Ohne Fenster lässt sich kein Text messen; Resize ordnet nach dem Einhängen.
  if not HasWindow then
    Exit;
  if FArranging or (FSearch = nil) or not FSearch.Visible then
  begin
    if not FArranging and (FSearchHost.Align <> alRight) then
    begin
      FSearchHost.Align := alRight;
      Height := ScaleValue(HeaderHeight);
    end;
    Exit;
  end;
  FArranging := True;
  try
    TextRight := FGreeting.Left + Max(FGreeting.Width, FInfo.Width) + ScaleValue(16);
    Below := ClientWidth - TextRight < ScaleValue(SearchWidth) + ScaleValue(20);
    if Below then
    begin
      FSearchHost.Align := alBottom;
      FSearchHost.Margins.SetBounds(FGreeting.Left, 0, ScaleValue(12), ScaleValue(8));
      FSearchHost.Height := ScaleValue(SearchRowHeight) - ScaleValue(8);
      Height := ScaleValue(HeaderHeight + SearchRowHeight);
    end
    else
    begin
      FSearchHost.Align := alRight;
      FSearchHost.Margins.SetBounds(8, 19, 12, 19);
      FSearchHost.Width := ScaleValue(SearchWidth);
      Height := ScaleValue(HeaderHeight);
    end;
  finally
    FArranging := False;
  end;
end;

class function TAtlasWelcomeHeaderFrame.GreetingText(AHour: Integer; const AFirstName: string): string;
begin
  case TAtlasWelcomeGreeting.DayTimeOf(AHour) of
    TAtlasDayTime.Morning:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeMorning);
    TAtlasDayTime.Day:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDay);
    TAtlasDayTime.Evening:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeEvening);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeNight);
  end;
  if AFirstName <> '' then
    Result := Result + ', ' + AFirstName;
end;

class function TAtlasWelcomeHeaderFrame.Thousands(AValue: Integer): string;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Invariant;
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    Settings.ThousandSeparator := '.';
    Settings.DecimalSeparator := ',';
  end
  else
  begin
    Settings.ThousandSeparator := ',';
    Settings.DecimalSeparator := '.';
  end;
  Result := FormatFloat('#,##0', AValue, Settings);
end;

class function TAtlasWelcomeHeaderFrame.StatusText(APhase: TAtlasServerPhase; AUnits: Integer;
  AIndexing: Boolean; APercent: Integer): string;
begin
  case APhase of
    TAtlasServerPhase.Starting:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeServerStarting);
    TAtlasServerPhase.Running:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeServerRunning);
    TAtlasServerPhase.Stopped:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeServerStopped);
    TAtlasServerPhase.Failed:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeServerFailed);
  else
    // Die Willkommensseite startet keinen Server; er kommt mit dem ersten Projekt.
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeServerIdle));
  end;
  if APhase <> TAtlasServerPhase.Running then
    Exit;
  if AIndexing and (APercent >= 0) then
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeIndexingPercent, [APercent])
  else if AIndexing then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.WelcomeIndexing)
  else if AUnits >= 0 then
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnits, [Thousands(AUnits)]);
end;

class function TAtlasWelcomeHeaderFrame.InfoText(const AInfo: TAtlasWelcomeHeaderInfo): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeVersion, [AInfo.Version]) + ' · ' +
    StatusText(AInfo.Phase, AInfo.Units, AInfo.Indexing, AInfo.Percent);
end;

end.
