unit Atlas.IDE.Commands.BlockFolds;

// Große Anweisungsblöcke einklappen (#2795, editor.blockFolds), IDE-Teil. Was
// gefaltet wird und wo die Marken stehen, rechnet Atlas.Core.Editor.BlockFolds;
// die Blöcke liefert der Server (atlas/blockFolds).
// - „Block einklappen“: innerster Block ab editor.blockFolds.minLines Zeilen um
//   die Schreibmarke. „Große Blöcke einklappen“: alle äußeren solchen Blöcke der
//   Datei. Beide setzen die Marken (ein Rückgängig-Schritt) und klappen nach einer
//   kurzen Pause (die IDE kennt die neue Region erst nach ihrem Durchlauf) über
//   IOTAElideActions an der Anfangsmarke zu.
// - „Blöcke aufklappen“: klappt die Regionen von Atlas auf und nimmt alle Marken
//   heraus.
// - Speichern: Ein Modul-Notifier hängt an jeder Datei, in der Atlas gefaltet
//   hat; BeforeSave klappt auf und nimmt die Marken heraus, damit sie nie in die
//   Datei kommen. Nach dem Speichern bleiben die Blöcke offen.
// Gesichert über TAtlasFeature.RegionFolds (#493). Nur im Hauptthread.

interface

uses
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Editor.BlockFolds,
  Atlas.IDE.Commands.EditorContext;

type
  TAtlasIdeBlockFolds = class(TAtlasEditorCommandContext)
  private const
    /// <summary>Pause nach dem Setzen der Marken, bis die IDE die Region kennt.</summary>
    cDelayMs = 300;
    /// <summary>Höchstens so lange auf die Blöcke des Servers warten.</summary>
    cTimeoutMs = 5000;
  private type
    /// <summary>Nimmt vor dem Speichern die Marken aus dem Puffer.</summary>
    TModuleNotifier = class(TInterfacedObject, IOTANotifier, IOTAModuleNotifier)
    private
      FFileName: string;
      FModule: IOTAModule;
      FIndex: Integer;
    public
      constructor Create(const AModule: IOTAModule);
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      function CheckOverwrite: Boolean;
      procedure ModuleRenamed(const NewName: string);
      /// <summary>Beim Modul abmelden; mehrfach aufrufbar.</summary>
      procedure Detach;
      /// <summary>Alle Puffer des Moduls aufklappen und ohne Marken lassen.</summary>
      procedure UnfoldModule;
    end;
    /// <summary>Zeitgeber, Notifier und was nach der Pause zugeklappt wird.</summary>
    TState = class
    private
      FTimer: TTimer;
      FNotifiers: TDictionary<string, TModuleNotifier>;
      /// <summary>Datei und Anfangsmarken, die nach der Pause zugeklappt werden.</summary>
      FPendingFile: string;
      FPendingOpen: TArray<TTextPosition>;
      FPendingCursor: TTextPosition;
      procedure TimerTick(Sender: TObject);
      procedure CollapsePending;
    public
      constructor Create;
      destructor Destroy; override;
    end;
  private class var
    FState: TState;
  private
    /// <summary>Blöcke der Datei AFileName mit dem Text AText; False mit Meldung, wenn der Server scheitert.</summary>
    class function FetchBlocks(const AFileName: string; out ABlocks: TArray<TAtlasBlockFold>): Boolean; static;
    /// <summary>Setzt die Marken für ABlocks und klappt sie nach der Pause zu.</summary>
    class procedure Fold(const AView: IOTAEditView; const ABlocks: TArray<TAtlasBlockFold>); static;
    /// <summary>Klappt die Regionen von Atlas in ABuffer auf und nimmt alle Marken heraus; False ohne Marken.</summary>
    class function Unfold(const ABuffer: IOTAEditBuffer): Boolean; static;
    /// <summary>Notifier an das Modul von ABuffer hängen, falls noch keiner hängt.</summary>
    class procedure Watch(const ABuffer: IOTAEditBuffer); static;
    class procedure Forget(ANotifier: TModuleNotifier); static;
    class function MinLines: Integer; static;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>editor.blockFolds an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl Atlas.FoldBlock.</summary>
    class procedure FoldAtCursor; static;
    /// <summary>Befehl Atlas.FoldLargeBlocks.</summary>
    class procedure FoldLarge; static;
    /// <summary>Befehl Atlas.UnfoldBlocks.</summary>
    class procedure UnfoldAll; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Plugin.Lsp.TextChanges,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Editor.RegionFolds,
  Atlas.IDE.Foundation.Settings,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.IDE.Foundation.EditorSnapshot;

/// <summary>Spalte des Editors (1-basiert) zu APosition im Text ALines.</summary>
function EditorPos(const ALines: TArray<string>; const APosition: TTextPosition; ATabWidth: Integer): TOTAEditPos;
begin
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(TTextLines.LineAt(ALines, APosition.Line), APosition.Character, ATabWidth);
end;

/// <summary>Schreibmarke auf jede Stelle in APositions setzen und dort zu- (ACollapse) bzw. aufklappen; danach
/// steht die Marke auf ACursor.</summary>
procedure Elide(const AView: IOTAEditView; const APositions: TArray<TTextPosition>; ACollapse: Boolean;
  const ACursor: TTextPosition);
var
  mElide: IOTAElideActions;
  mLines: TArray<string>;
  mTabWidth: Integer;
  mPosition: TTextPosition;
begin
  if not Supports(AView, IOTAElideActions, mElide) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitAtLineFeed(TAtlasEditorBuffer.Text(AView.Buffer));
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  for mPosition in APositions do
  begin
    AView.CursorPos := EditorPos(mLines, mPosition, mTabWidth);
    if ACollapse then
    begin
      mElide.ElideNearestBlock;
    end
    else
    begin
      mElide.UnElideNearestBlock;
    end;
  end;
  AView.CursorPos := EditorPos(mLines, ACursor, mTabWidth);
  AView.MoveViewToCursor;
  AView.Paint;
end;

{ TAtlasIdeBlockFolds.TModuleNotifier }

constructor TAtlasIdeBlockFolds.TModuleNotifier.Create(const AModule: IOTAModule);
begin
  inherited Create;
  FModule := AModule;
  FFileName := AnsiLowerCase(AModule.FileName);
  FIndex := -1;
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.AfterSave;
begin
  // Die Blöcke bleiben nach dem Speichern offen; neu falten setzte die Datei wieder auf geändert.
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.BeforeSave;
begin
  TAtlasGuard.Run(TAtlasFeature.RegionFolds, UnfoldModule);
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.UnfoldModule;
var
  mIndex: Integer;
  mBuffer: IOTAEditBuffer;
begin
  if FModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FModule.ModuleFileCount - 1 do
  begin
    if Supports(FModule.ModuleFileEditors[mIndex], IOTAEditBuffer, mBuffer) then
    begin
      TAtlasIdeBlockFolds.Unfold(mBuffer);
    end;
  end;
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.Destroyed;
begin
  Detach;
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.Modified;
begin
  // Änderungen am Puffer betreffen die Marken nicht.
end;

function TAtlasIdeBlockFolds.TModuleNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.ModuleRenamed(const NewName: string);
begin
  // Unter dem neuen Namen findet Watch das Modul nicht mehr; ein zweiter Notifier schadet nicht.
end;

procedure TAtlasIdeBlockFolds.TModuleNotifier.Detach;
var
  mKeep: IOTANotifier;
  mModule: IOTAModule;
begin
  // Selbst festhalten: Das Abmelden gibt die Referenz der IDE frei.
  mKeep := Self;
  TAtlasIdeBlockFolds.Forget(Self);
  mModule := FModule;
  FModule := nil;
  if (mModule <> nil) and (FIndex >= 0) then
  begin
    mModule.RemoveNotifier(FIndex);
  end;
  FIndex := -1;
end;

{ TAtlasIdeBlockFolds }

{ TAtlasIdeBlockFolds.TState }

constructor TAtlasIdeBlockFolds.TState.Create;
begin
  inherited Create;
  FNotifiers := TDictionary<string, TModuleNotifier>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasIdeBlockFolds.cDelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeBlockFolds.TState.Destroy;
var
  mNotifier: TModuleNotifier;
begin
  FreeAndNil(FTimer);
  for mNotifier in FNotifiers.Values.ToArray do
  begin
    mNotifier.Detach;
  end;
  FreeAndNil(FNotifiers);
  FPendingOpen := nil;
  inherited Destroy;
end;

procedure TAtlasIdeBlockFolds.TState.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.RegionFolds, CollapsePending);
end;

procedure TAtlasIdeBlockFolds.TState.CollapsePending;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.TopSourceView;
  if (mView <> nil) and SameText(mView.Buffer.FileName, FPendingFile) then
  begin
    Elide(mView, FPendingOpen, True, FPendingCursor);
  end;
  FPendingOpen := nil;
  FPendingFile := '';
end;

{ TAtlasIdeBlockFolds }

class procedure TAtlasIdeBlockFolds.Install;
begin
  if FState = nil then
  begin
    FState := TState.Create;
  end;
end;

class procedure TAtlasIdeBlockFolds.Uninstall;
begin
  FreeAndNil(FState);
end;

class function TAtlasIdeBlockFolds.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.BlockFolds;
end;

class function TAtlasIdeBlockFolds.MinLines: Integer;
begin
  Result := TAtlasIdeSettings.Current.BlockFoldsMinLines;
end;

class procedure TAtlasIdeBlockFolds.Forget(ANotifier: TModuleNotifier);
begin
  if (FState <> nil) and FState.FNotifiers.ContainsKey(ANotifier.FFileName) and
    (FState.FNotifiers[ANotifier.FFileName] = ANotifier) then
  begin
    FState.FNotifiers.Remove(ANotifier.FFileName);
  end;
end;

class procedure TAtlasIdeBlockFolds.Watch(const ABuffer: IOTAEditBuffer);
var
  mModule: IOTAModule;
  mNotifier: TModuleNotifier;
begin
  mModule := ABuffer.Module;
  if (FState = nil) or (mModule = nil) or FState.FNotifiers.ContainsKey(AnsiLowerCase(mModule.FileName)) then
  begin
    Exit;
  end;
  mNotifier := TModuleNotifier.Create(mModule);
  FState.FNotifiers.Add(mNotifier.FFileName, mNotifier);
  mNotifier.FIndex := mModule.AddNotifier(mNotifier);
end;

class function TAtlasIdeBlockFolds.FetchBlocks(const AFileName: string; out ABlocks: TArray<TAtlasBlockFold>): Boolean;
var
  mAnswer: TJSONValue;
begin
  ABlocks := nil;
  try
    mAnswer := Session.RunRequest(TAtlasBlockFolds.cMethod, TAtlasBlockFolds.Params(TLspSession.PathToUri(AFileName)),
      cTimeoutMs, nil);
  except
    on E: ELspClientError do
    begin
      Say(E.Message);
      Exit(False);
    end;
  end;
  try
    ABlocks := TAtlasBlockFolds.FromJson(mAnswer);
  finally
    mAnswer.Free;
  end;
  Result := True;
end;

class procedure TAtlasIdeBlockFolds.Fold(const AView: IOTAEditView; const ABlocks: TArray<TAtlasBlockFold>);
var
  mText: string;
  mBlock: TAtlasBlockFold;
  mCursor: TTextPosition;
  mCaret: TAtlasEditorCaret;
begin
  if (FState = nil) or not Caret(mCaret) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mCursor := TTextPosition.Create(mCaret.Row, mCaret.Character);
  FState.FPendingOpen := nil;
  for mBlock in ABlocks do
  begin
    FState.FPendingOpen := FState.FPendingOpen + [mBlock.OpenPos];
    // Eine Schreibmarke im gefalteten Teil wäre unsichtbar: an den Anfang des Blocks.
    if (mCursor.Line > mBlock.OpenPos.Line) and (mCursor.Line <= mBlock.ClosePos.Line) then
    begin
      mCursor := mBlock.OpenPos;
    end;
  end;
  Watch(AView.Buffer);
  TAtlasEditorSnapshots.WriteEdits(AView.Buffer, mText, TAtlasBlockFolds.FoldEdits(mText, ABlocks));
  FState.FPendingFile := AView.Buffer.FileName;
  FState.FPendingCursor := mCursor;
  FState.FTimer.Enabled := False;
  FState.FTimer.Enabled := True;
end;

class function TAtlasIdeBlockFolds.Unfold(const ABuffer: IOTAEditBuffer): Boolean;
var
  mText: string;
  mMarkers: TArray<TAtlasBlockMarker>;
  mFolded: TArray<TAtlasFoldedBlock>;
  mPositions: TArray<TTextPosition>;
  mPair: TAtlasFoldedBlock;
  mCursor: TOTAEditPos;
begin
  mText := TAtlasEditorBuffer.Text(ABuffer);
  mMarkers := TAtlasBlockFolds.Markers(mText);
  Result := Length(mMarkers) > 0;
  if not Result then
  begin
    Exit;
  end;
  // Erst aufklappen (außen zuerst), solange die Regionen noch stehen, dann die Marken heraus.
  mFolded := TAtlasBlockFolds.Folded(mMarkers);
  mPositions := nil;
  for mPair in mFolded do
  begin
    mPositions := mPositions + [TTextPosition.Create(mPair.Open.Line, 0)];
  end;
  if ABuffer.TopView <> nil then
  begin
    mCursor := ABuffer.TopView.CursorPos;
    Elide(ABuffer.TopView, mPositions, False, TTextPosition.Create(mCursor.Line - 1, 0));
    ABuffer.TopView.CursorPos := mCursor;
  end;
  TAtlasEditorSnapshots.WriteEdits(ABuffer, mText, TAtlasBlockFolds.RemoveEdits(mMarkers));
end;

class procedure TAtlasIdeBlockFolds.FoldAtCursor;
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mBlocks: TArray<TAtlasBlockFold>;
  mIndex: Integer;
begin
  if not Enabled or not Current(mView, mFileName, mLines, mSelection) or not FetchBlocks(mFileName, mBlocks) then
  begin
    Exit;
  end;
  mIndex := TAtlasBlockFolds.Innermost(mBlocks, mSelection.StartPos.Line, MinLines);
  if mIndex < 0 then
  begin
    Say(Format(TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.NoBlockAtCursor), [MinLines]));
    Exit;
  end;
  Fold(mView, TArray<TAtlasBlockFold>.Create(mBlocks[mIndex]));
end;

class procedure TAtlasIdeBlockFolds.FoldLarge;
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mBlocks: TArray<TAtlasBlockFold>;
begin
  if not Enabled or not Current(mView, mFileName, mLines, mSelection) or not FetchBlocks(mFileName, mBlocks) then
  begin
    Exit;
  end;
  mBlocks := TAtlasBlockFolds.Large(mBlocks, MinLines);
  if Length(mBlocks) = 0 then
  begin
    Say(Format(TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.NoLargeBlocks), [MinLines]));
    Exit;
  end;
  Fold(mView, mBlocks);
end;

class procedure TAtlasIdeBlockFolds.UnfoldAll;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.TopSourceView;
  if not Enabled or (mView = nil) then
  begin
    Exit;
  end;
  if not Unfold(mView.Buffer) then
  begin
    Say(TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.NoFoldedBlocks));
  end;
end;

end.
