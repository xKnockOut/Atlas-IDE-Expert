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
    cHeaderHeight = 64;
    cSymbolSize = 40;
    cSearchWidth = 320;
    /// <summary>Höhe der Suchzeile unter dem Gruß, wenn das Feld daneben keinen Platz hat.</summary>
    cSearchRowHeight = 36;
  private
    FSymbol: TAtlasSymbolImage;
    FGreeting: TLabel;
    FInfo: TLabel;
    FSearchHost: TPanel;
    FSearch: TAtlasWelcomeSearchBox;
    FData: TAtlasWelcomeHeaderInfo;
    // ShowInfo lief schon einmal: Danach zählt nur, was sich geändert hat.
    FFilled: Boolean;
    FArranging: Boolean;
    procedure Arrange;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Gruß und Kurzstatus zeigen; gleiche Angaben wie zuletzt lassen den Kopf unberührt (jede Änderung im
    /// Statusfeld fragt nach, meist ohne Folgen für den Kopf).</summary>
    procedure ShowInfo(const AInfo: TAtlasWelcomeHeaderInfo);
    /// <summary>Nach Themen-, Sprach- oder Einstellungswechsel: Symbol neu zeichnen (die Variante folgt dem
    /// Hintergrund), und das nächste ShowInfo setzt alles neu.</summary>
    procedure Renew;
    /// <summary>Zeigen A und B denselben Kopf?</summary>
    class function SameInfo(const A, B: TAtlasWelcomeHeaderInfo): Boolean; static;
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
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings;

{ TAtlasWelcomeHeaderFrame }

constructor TAtlasWelcomeHeaderFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := ScaleValue(cHeaderHeight);
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Self;
  FSymbol.LogicalSize := cSymbolSize;
  FSymbol.Left := FSymbol.ScaleValue(8);
  FSymbol.Top := (cHeaderHeight - cSymbolSize) div 2;
  FGreeting := TLabel.Create(Self);
  FGreeting.Parent := Self;
  FGreeting.Left := FGreeting.ScaleValue(cSymbolSize) + FGreeting.ScaleValue(20);
  FGreeting.Top := FGreeting.ScaleValue(10);
  FGreeting.Font.Size := 14;
  FGreeting.Font.Style := [fsBold];
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.Left := FGreeting.Left;
  FInfo.Top := FInfo.ScaleValue(38);
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
  if FFilled and SameInfo(FData, AInfo) then
  begin
    Exit;
  end;
  FFilled := True;
  FData := AInfo;
  if AInfo.Greeting then
  begin
    FGreeting.Caption := GreetingText(AInfo.Hour, AInfo.FirstName);
  end
  else
  begin
    FGreeting.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeHeaderTitle);
  end;
  FInfo.Caption := InfoText(AInfo);
  Arrange;
end;

procedure TAtlasWelcomeHeaderFrame.Renew;
begin
  FFilled := False;
  FSymbol.Invalidate;
end;

class function TAtlasWelcomeHeaderFrame.SameInfo(const A, B: TAtlasWelcomeHeaderInfo): Boolean;
begin
  Result := (A.Greeting = B.Greeting) and (A.Hour = B.Hour) and (A.FirstName = B.FirstName) and
    (A.Version = B.Version) and (A.Phase = B.Phase) and (A.Units = B.Units) and (A.Indexing = B.Indexing) and
    (A.Percent = B.Percent);
end;

procedure TAtlasWelcomeHeaderFrame.ShowSearch(AVisible: Boolean);
begin
  // Unverändert: nichts neu anordnen.
  if (FSearch <> nil) and (FSearch.Visible = AVisible) and ((FSearchHost.Width > 0) = AVisible) then
  begin
    Exit;
  end;
  if (FSearch = nil) and not AVisible and (FSearchHost.Width = 0) then
  begin
    Exit;
  end;
  if AVisible and (FSearch = nil) then
  begin
    FSearch := TAtlasWelcomeSearchBox.Create(Self);
    FSearch.Parent := FSearchHost;
    FSearch.Align := alClient;
  end;
  if FSearch <> nil then
  begin
    if not AVisible then
    begin
      FSearch.Clear;
    end;
    FSearch.Visible := AVisible;
  end;
  if AVisible then
  begin
    FSearchHost.Width := ScaleValue(cSearchWidth);
  end
  else
  begin
    FSearchHost.Width := 0;
  end;
  Arrange;
end;

procedure TAtlasWelcomeHeaderFrame.Resize;
begin
  inherited;
  Arrange;
end;

procedure TAtlasWelcomeHeaderFrame.Arrange;
var
  mTextRight: Integer;
  mBelow: Boolean;
begin
  // Reicht die Breite nicht für Gruß und Suchfeld nebeneinander, steht das Feld in einer
  // eigenen Zeile darunter (schmales Fenster „Atlas-Start“).
  // Ohne Fenster lässt sich kein Text messen; Resize ordnet nach dem Einhängen.
  if not HasWindow then
  begin
    Exit;
  end;
  if FArranging or (FSearch = nil) or not FSearch.Visible then
  begin
    if not FArranging and (FSearchHost.Align <> alRight) then
    begin
      FSearchHost.Align := alRight;
      Height := ScaleValue(cHeaderHeight);
    end;
    Exit;
  end;
  FArranging := True;
  try
    mTextRight := FGreeting.Left + Max(FGreeting.Width, FInfo.Width) + ScaleValue(16);
    mBelow := ClientWidth - mTextRight < ScaleValue(cSearchWidth) + ScaleValue(20);
    if mBelow then
    begin
      FSearchHost.Align := alBottom;
      FSearchHost.Margins.SetBounds(FGreeting.Left, 0, ScaleValue(12), ScaleValue(8));
      FSearchHost.Height := ScaleValue(cSearchRowHeight) - ScaleValue(8);
      Height := ScaleValue(cHeaderHeight + cSearchRowHeight);
    end
    else
    begin
      FSearchHost.Align := alRight;
      FSearchHost.Margins.SetBounds(8, 19, 12, 19);
      FSearchHost.Width := ScaleValue(cSearchWidth);
      Height := ScaleValue(cHeaderHeight);
    end;
  finally
    FArranging := False;
  end;
end;

class function TAtlasWelcomeHeaderFrame.GreetingText(AHour: Integer; const AFirstName: string): string;
begin
  case TAtlasWelcomeGreeting.DayTimeOf(AHour) of
    TAtlasDayTime.Morning:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeMorning);
    TAtlasDayTime.Day:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDay);
    TAtlasDayTime.Evening:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeEvening);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNight);
  end;
  if AFirstName <> '' then
  begin
    Result := Result + ', ' + AFirstName;
  end;
end;

class function TAtlasWelcomeHeaderFrame.Thousands(AValue: Integer): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    mSettings.ThousandSeparator := '.';
    mSettings.DecimalSeparator := ',';
  end
  else
  begin
    mSettings.ThousandSeparator := ',';
    mSettings.DecimalSeparator := '.';
  end;
  Result := FormatFloat('#,##0', AValue, mSettings);
end;

class function TAtlasWelcomeHeaderFrame.StatusText(APhase: TAtlasServerPhase; AUnits: Integer;
  AIndexing: Boolean; APercent: Integer): string;
begin
  case APhase of
    TAtlasServerPhase.Starting:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeServerStarting);
    TAtlasServerPhase.Running:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeServerRunning);
    TAtlasServerPhase.Stopped:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeServerStopped);
    TAtlasServerPhase.Failed:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeServerFailed);
  else
    // Die Willkommensseite startet keinen Server; er kommt mit dem ersten Projekt.
    Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeServerIdle));
  end;
  if APhase <> TAtlasServerPhase.Running then
  begin
    Exit;
  end;
  if AIndexing and (APercent >= 0) then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIndexingPercent, [APercent]);
  end
  else if AIndexing then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeIndexing);
  end
  else if AUnits >= 0 then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnits, [Thousands(AUnits)]);
  end;
end;

class function TAtlasWelcomeHeaderFrame.InfoText(const AInfo: TAtlasWelcomeHeaderInfo): string;
begin
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeVersion, [AInfo.Version]) + ' · ' +
    StatusText(AInfo.Phase, AInfo.Units, AInfo.Indexing, AInfo.Percent);
end;

end.
