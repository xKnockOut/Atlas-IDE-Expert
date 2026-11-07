unit Atlas.IDE.Editor.Minimap;

// Minimap neben der Scrollleiste (#873, experimentell) in der IDE:
// - Jedes Editorfenster bekommt neben dem Editor einen Streifen
//   (TAtlasMinimapView, alRight bzw. alLeft nach editor.minimap.side im
//   Eltern-Steuerelement des Editors „Editor“), wie die Übersichtsleiste
//   (#519); beide können nebeneinander stehen.
// - Ein Zeitgeber (100 ms) führt die Ansicht vorn nach: sichtbarer Bereich
//   und Cursor sofort; den Text aus TAtlasEditorSnapshots (liest den Puffer
//   nur nach Änderungen) erst nach einer Tipp-Pause, zerlegt in Balken im
//   Hintergrund (TAtlasMinimap.Runs), das Ergebnis über TAtlasMainThread.
//   Der Streifen zeichnet danach nur geänderte Zeilen neu.
// - Gliederung (Überschriften, Routine am Cursor) aus TAtlasIdeOutlineCache
//   (gemeinsam mit Gliederung, Brotkrumen und mitlaufendem Kopf), Marken über
//   TAtlasIdeOverviewRuler.CollectMarks (Befunde, Treffer des markierten
//   Texts, Änderungen).
// - Faltung: Atlas.IDE.Editor.MinimapFolds (aus den gemalten Zeilen).
// - Ziehen setzt die oberste Zeile (SetTopLeft), ein Klick springt
//   (TAtlasIdeNavigation) oder scrollt nur (editor.minimap.clickJumps).
// - Minimap der IDE: Hinweis „Zwei Minimaps sichtbar“ über
//   Atlas.IDE.Editor.MinimapNotice.
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE und Abbau übernimmt TAtlasEditorBarHost (#1248).
// editor.minimap oder experimental.enabled aus: alle Streifen weg, kein
// Zeichen-Ereignis. Nur im Hauptthread.

interface

type
  TAtlasIdeMinimap = class
  private class var
    FState: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Minimap an: editor.minimap (wirksam nur mit experimental.enabled) und Sicherung.</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Editor.Minimap,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Editor.OverviewRuler,
  Atlas.IDE.Editor.MinimapFolds,
  Atlas.IDE.Editor.MinimapNotice;

const
  cTickMs = 100;
  /// <summary>Tipp-Pause, bevor der Text neu zerlegt wird.</summary>
  cQuietMs = 300;

type
  TMinimapState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FFolds: TAtlasIdeMinimapFolds;
    FOptions: TAtlasMinimapOptions;
    FColorsSet: Boolean;
    // Inhalt der Ansicht vorn.
    FFileName: string;
    FVersion: Cardinal;
    FChangedAt: UInt64;
    FAppliedVersion: Cardinal;
    /// <summary>Für die Datei liegt schon ein zerlegter Stand vor.</summary>
    FHasContent: Boolean;
    FLines: TArray<string>;
    FRuns: TAtlasMinimapLines;
    FTabWidth: Integer;
    FWorker: TThread;
    FWorking: Boolean;
    FRequest: Integer;
    FStamp: Cardinal;
    /// <summary>Streifen, der den Inhalt zuletzt bekam (Fensterwechsel).</summary>
    FContentView: TAtlasMinimapView;
    // Treffer des markierten Texts.
    FTerm: string;
    FTermVersion: Cardinal;
    FSearchLines: TArray<Integer>;
    // Hinweis bei sichtbarer IDE-Minimap.
    FNotice: TAtlasIdeMinimapNotice;
    procedure Tick(Sender: TObject);
    function ActiveMinimap: TAtlasMinimapView;
    function CreateView: TAtlasMinimapView;
    procedure Place(AView: TAtlasMinimapView; AParent: TWinControl);
    procedure Update;
    procedure UpdateContent(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
    procedure StartWorker(const AText: string; AVersion: Cardinal; AMaxColumn, ATabWidth: Integer);
    procedure Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal; const ALines: TArray<string>;
      const ARuns: TAtlasMinimapLines);
    procedure UpdateMarks(const AView: IOTAEditView; AMinimap: TAtlasMinimapView; ALineCount: Integer);
    procedure Scroll(AMinimap: TAtlasMinimapView; ATopLine: Integer);
    procedure Jump(AMinimap: TAtlasMinimapView; ALine: Integer);
    procedure UpdateOutline(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
    procedure HideIdeMinimap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(AView: TControl);
    procedure ApplySettings;
    procedure ApplyTheme;
  end;

function CurrentOptions: TAtlasMinimapOptions;
begin
  Result := TAtlasMinimap.Options(TAtlasIdeSettings.Current);
end;

function SameOptions(const A, B: TAtlasMinimapOptions): Boolean;
begin
  Result := (A.Render = B.Render) and (A.Width = B.Width) and (A.Scale = B.Scale) and (A.MaxColumn = B.MaxColumn) and
    (A.Side = B.Side) and (A.Slider = B.Slider) and (A.SectionHeaders = B.SectionHeaders) and
    (A.HighlightMethod = B.HighlightMethod) and (A.Markers = B.Markers) and (A.ClickJumps = B.ClickJumps);
end;

/// <summary>Minimap an den Rand ASide ihres Eltern-Steuerelements.</summary>
procedure PlaceView(AView: TAtlasMinimapView; ASide: TAtlasMinimapSide);
var
  mParent: TWinControl;
begin
  mParent := AView.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  // Zuerst ganz an den Rand, dann ausrichten: so steht die Minimap außen.
  AView.Align := alNone;
  if ASide = TAtlasMinimapSide.Left then
  begin
    AView.Left := -AView.Width;
    AView.Align := alLeft;
  end
  else
  begin
    AView.Left := mParent.ClientWidth;
    AView.Align := alRight;
  end;
end;

/// <summary>Atlas-Minimap ausschalten (Knopf im Hinweis).</summary>
procedure TurnOff;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.Minimap := False;
  TAtlasIdeSettings.Update(mSettings);
  // Nach dem laufenden Ereignis: der Zustand gibt sich dabei selbst frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Minimap,
    procedure
    begin
      TAtlasIdeMinimap.ApplySettings;
    end);
end;

/// <summary>Knöpfe des Hinweises; sie wirken nur, solange die Minimap läuft.</summary>
function HideIdeAction: TProc;
begin
  Result :=
    procedure
    begin
      if TAtlasIdeMinimap.FState <> nil then
      begin
        TMinimapState(TAtlasIdeMinimap.FState).HideIdeMinimap;
      end;
    end;
end;

function TurnOffAction: TProc;
begin
  Result :=
    procedure
    begin
      if TAtlasIdeMinimap.FState <> nil then
      begin
        TurnOff;
      end;
    end;
end;

{ TMinimapState }

constructor TMinimapState.Create;
begin
  inherited Create;
  FTabWidth := 4;
  FHost := TAtlasEditorBarHost.Create('Minimap', TAtlasFeature.Minimap,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateView;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasMinimapView(ABar), AEditorParent);
    end);
  FHost.OnRemoved :=
    procedure(ABar: TControl)
    begin
      Removed(ABar);
    end;
  FOptions := CurrentOptions;
  FFolds := TAtlasIdeMinimapFolds.Create;
  FNotice := TAtlasIdeMinimapNotice.Create(HideIdeAction(), TurnOffAction());
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TMinimapState.Destroy;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FFolds);
  // Ein laufender Zerleger meldet sich über die Warteschlange; Inc verwirft sein Ergebnis.
  Inc(FRequest);
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FreeAndNil(FNotice);
  FHost.Free;
  inherited Destroy;
end;

procedure TMinimapState.Removed(AView: TControl);
begin
  if FContentView = AView then
  begin
    FContentView := nil;
  end;
end;

procedure TMinimapState.ApplySettings;
var
  mOptions: TAtlasMinimapOptions;
begin
  mOptions := CurrentOptions;
  if SameOptions(mOptions, FOptions) then
  begin
    Exit;
  end;
  // Andere höchste Spalte: neu zerlegen.
  if mOptions.MaxColumn <> FOptions.MaxColumn then
  begin
    FHasContent := False;
  end;
  FOptions := mOptions;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasMinimapView(ABar).SetOptions(FOptions);
      PlaceView(TAtlasMinimapView(ABar), FOptions.Side);
    end);
end;

procedure TMinimapState.ApplyTheme;
begin
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasMinimapView(ABar).SetColors(TAtlasIdeStyle.Colors);
    end);
end;

function TMinimapState.ActiveMinimap: TAtlasMinimapView;
begin
  Result := TAtlasMinimapView(FHost.ActiveBar);
end;

procedure TMinimapState.Place(AView: TAtlasMinimapView; AParent: TWinControl);
begin
  if AView.Parent = AParent then
  begin
    Exit;
  end;
  AView.Parent := AParent;
  PlaceView(AView, FOptions.Side);
end;

/// <summary>Eigene Methode: Jeder Streifen braucht seine eigene gefangene Variable.</summary>
function TMinimapState.CreateView: TAtlasMinimapView;
var
  mView: TAtlasMinimapView;
begin
  mView := TAtlasMinimapView.Create(nil);
  Result := mView;
  mView.SetOptions(FOptions);
  mView.SetColors(TAtlasIdeStyle.Colors);
  mView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Minimap,
        procedure
        begin
          Scroll(mView, ATopLine);
        end);
    end;
  mView.OnJump :=
    procedure(ALine: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Minimap,
        procedure
        begin
          Jump(mView, ALine);
        end);
    end;
end;

procedure TMinimapState.StartWorker(const AText: string; AVersion: Cardinal; AMaxColumn, ATabWidth: Integer);
var
  mRequest: Integer;
  mFileName: string;
begin
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  Inc(FRequest);
  mRequest := FRequest;
  mFileName := FFileName;
  FWorking := True;
  FWorker := TThread.CreateAnonymousThread(
    procedure
    var
      Lines: TArray<string>;
      Runs: TAtlasMinimapLines;
    begin
      try
        Lines := TTextLines.SplitLines(AText);
        Runs := TAtlasMinimap.Runs(Lines, AMaxColumn, ATabWidth);
      except
        Lines := nil;
        Runs := nil;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Minimap,
        procedure
        begin
          if TAtlasIdeMinimap.FState <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Minimap,
              procedure
              begin
                if TAtlasIdeMinimap.FState <> nil then
                begin
                  TMinimapState(TAtlasIdeMinimap.FState).Accept(mRequest, mFileName, AVersion, Lines, Runs);
                end;
              end);
          end;
        end);
    end);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TMinimapState.Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal;
  const ALines: TArray<string>; const ARuns: TAtlasMinimapLines);
var
  mMinimap: TAtlasMinimapView;
begin
  if ARequest <> FRequest then
  begin
    Exit;
  end;
  FWorking := False;
  if not SameText(AFileName, FFileName) then
  begin
    Exit;
  end;
  FLines := ALines;
  FRuns := ARuns;
  FAppliedVersion := AVersion;
  FHasContent := True;
  // Neue Treffer zum neuen Text.
  FTermVersion := 0;
  mMinimap := ActiveMinimap;
  if mMinimap <> nil then
  begin
    mMinimap.SetContent(FLines, FRuns, FTabWidth);
    FContentView := mMinimap;
  end;
end;

procedure TMinimapState.UpdateContent(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
var
  mSnapshot: TAtlasEditorSnapshot;
  mFirst: Boolean;
begin
  mSnapshot := TAtlasEditorSnapshots.Get(AView);
  mFirst := not SameText(mSnapshot.FileName, FFileName);
  if mFirst then
  begin
    FFileName := mSnapshot.FileName;
    FHasContent := False;
    FVersion := mSnapshot.Version;
    FLines := nil;
    FRuns := nil;
    FFolds.Reset;
    FTermVersion := 0;
    FStamp := 0;
    AMinimap.SetFolds(nil);
    AMinimap.SetOutline(nil);
    AMinimap.SetMarks(nil);
    AMinimap.SetContent(nil, nil, FTabWidth);
    FContentView := AMinimap;
  end;
  if mSnapshot.Version <> FVersion then
  begin
    FVersion := mSnapshot.Version;
    FChangedAt := TThread.GetTickCount64;
  end;
  // Erster Stand sofort, Änderungen nach der Tipp-Pause; nie zwei Zerleger zugleich.
  if not FWorking and (not FHasContent or ((FAppliedVersion <> FVersion) and
    (TThread.GetTickCount64 - FChangedAt >= cQuietMs))) then
  begin
    FTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
    StartWorker(mSnapshot.Text, FVersion, FOptions.MaxColumn, FTabWidth);
  end;
end;

procedure TMinimapState.UpdateMarks(const AView: IOTAEditView; AMinimap: TAtlasMinimapView; ALineCount: Integer);
var
  mBlock: IOTAEditBlock;
  mTerm: string;
begin
  if not FOptions.Markers then
  begin
    AMinimap.SetMarks(nil);
    Exit;
  end;
  mTerm := '';
  mBlock := AView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) and (mBlock.StartingRow = mBlock.EndingRow) then
  begin
    TAtlasOverview.SearchTerm(mBlock.Text, mTerm);
  end;
  if mTerm = '' then
  begin
    FSearchLines := nil;
  end
  else if (mTerm <> FTerm) or (FTermVersion <> FAppliedVersion) then
  begin
    FSearchLines := TAtlasOverview.Occurrences(FLines, mTerm);
  end;
  FTerm := mTerm;
  FTermVersion := FAppliedVersion;
  AMinimap.SetMarks(TAtlasIdeOverviewRuler.CollectMarks(AView, ALineCount, TAtlasMinimap.MarkerKinds, FTerm,
    FSearchLines));
end;

procedure TMinimapState.Update;
var
  mMinimap: TAtlasMinimapView;
  mView: IOTAEditView;
  mLineCount: Integer;
begin
  ApplySettings;
  FHost.Ensure;
  mMinimap := ActiveMinimap;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mMinimap = nil) or (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  if not FColorsSet then
  begin
    ApplyTheme;
    FColorsSet := True;
  end;
  mLineCount := mView.Buffer.GetLinesInBuffer;
  // Anderes Editorfenster vorn: Es übernimmt Inhalt und Gliederung.
  if mMinimap <> FContentView then
  begin
    mMinimap.SetContent(FLines, FRuns, FTabWidth);
    FContentView := mMinimap;
    FStamp := 0;
  end;
  UpdateContent(mView, mMinimap);
  mMinimap.SetFolds(FFolds.Update(FFileName, mLineCount));
  if not mMinimap.SliderDragging then
  begin
    mMinimap.SetView(mView.TopRow - 1, mView.BottomRow - 1, mView.CursorPos.Line - 1);
  end;
  UpdateOutline(mView, mMinimap);
  UpdateMarks(mView, mMinimap, mLineCount);
  FNotice.Check(mMinimap);
end;

/// <summary>Überschriften und Routine am Cursor aus der Gliederung, wenn sie neu ist.</summary>
procedure TMinimapState.UpdateOutline(const AView: IOTAEditView; AMinimap: TAtlasMinimapView);
var
  mSnapshot: TAtlasOutlineSnapshot;
begin
  if not FOptions.SectionHeaders and not FOptions.HighlightMethod then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(AView);
  if (mSnapshot.Status = TAtlasOutlineStatus.Ready) and SameText(mSnapshot.FileName, FFileName) and
    (mSnapshot.Stamp <> FStamp) then
  begin
    FStamp := mSnapshot.Stamp;
    AMinimap.SetOutline(mSnapshot.Nodes);
  end;
end;

procedure TMinimapState.Scroll(AMinimap: TAtlasMinimapView; ATopLine: Integer);
var
  mView: IOTAEditView;
  mRows: Integer;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (AMinimap <> ActiveMinimap) or (mView = nil) or (mView.Buffer = nil) or (ATopLine < 0) then
  begin
    Exit;
  end;
  mRows := mView.BottomRow - mView.TopRow;
  mView.SetTopLeft(ATopLine + 1, mView.LeftColumn);
  mView.Paint;
  // Sofort nachführen, damit das Ziehen flüssig bleibt.
  AMinimap.SetView(ATopLine, ATopLine + mRows, mView.CursorPos.Line - 1);
end;

procedure TMinimapState.Jump(AMinimap: TAtlasMinimapView; ALine: Integer);
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (AMinimap <> ActiveMinimap) or (mView = nil) or (mView.Buffer = nil) or (ALine < 0) then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(mView.Buffer.FileName, ALine, 0);
end;

procedure TMinimapState.HideIdeMinimap;
begin
  // Für diese Sitzung; die Einstellung der IDE bleibt.
  FNotice.HideIde := True;
  FHost.ForEach(
    procedure(ABar: TControl)
    var
      mIde: TControl;
    begin
      mIde := TAtlasIdeMinimapNotice.IdeMinimap(ABar.Parent);
      if mIde <> nil then
      begin
        mIde.Visible := False;
      end;
    end);
end;

procedure TMinimapState.Tick(Sender: TObject);
begin
  // Schnellschalter, Hauptschalter und Sicherung wirken ohne eigenes Ereignis.
  if not TAtlasIdeMinimap.Active then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Minimap,
      procedure
      begin
        TAtlasIdeMinimap.ApplySettings;
      end);
    FTimer.Enabled := False;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Minimap,
    procedure
    begin
      Update;
    end);
end;

{ TAtlasIdeMinimap }

class function TAtlasIdeMinimap.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Minimap and not TAtlasGuard.Disabled(TAtlasFeature.Minimap);
end;

class procedure TAtlasIdeMinimap.Install;
begin
  FreeAndNil(FState);
  if Active then
  begin
    FState := TMinimapState.Create;
  end;
end;

class procedure TAtlasIdeMinimap.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeMinimap.ApplySettings;
begin
  // Aus: alle Streifen weg, der Editor bekommt seine Breite zurück.
  if not Active then
  begin
    FreeAndNil(FState);
    Exit;
  end;
  if FState = nil then
  begin
    FState := TMinimapState.Create;
  end
  else
  begin
    TMinimapState(FState).ApplySettings;
  end;
end;

class procedure TAtlasIdeMinimap.ThemeChanged;
begin
  if FState <> nil then
  begin
    TMinimapState(FState).ApplyTheme;
  end;
end;

end.
