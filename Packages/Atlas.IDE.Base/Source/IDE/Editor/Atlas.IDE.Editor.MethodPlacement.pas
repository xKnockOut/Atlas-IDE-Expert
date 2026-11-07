unit Atlas.IDE.Editor.MethodPlacement;

// Methodenrümpfe in Deklarationsreihenfolge (#660) im Editor. Ordnen und
// Einfügestelle rechnet der Server (atlas.server.methodOrder), Argumente,
// Antwort und die eine Änderung Atlas.Core.Editor.MethodPlacement; hier
// bleiben Puffer, Zeitgeber, Vorschau und Schreiben.
// - Neue Rümpfe: Nach jeder Änderung wartet ein Zeitgeber, bis der Editor
//   400 ms ruht, und vergleicht den Puffer mit dem letzten Stand. Ist ein
//   Methodenkopf dazugekommen (Strg+Umschalt+C der IDE, Atlas-Aktionen wie
//   „Methode anlegen“), fragt Atlas den Server, wohin der Rumpf gehört.
//   Steht er falsch, nimmt Atlas den letzten Schritt zurück und schreibt
//   Vervollständigung und Verschieben als einen Schritt: Ein Strg+Z stellt
//   den Stand davor her. Lässt sich der Schritt nicht sauber zurücknehmen
//   (mehrere Schritte, andere Änderungen dazwischen), wird nur verschoben,
//   als eigener Schritt. Die Schreibmarke wandert im Rumpf mit.
// - Befehl „implementation wie Klasse ordnen“ (Menü Atlas, Palette,
//   Kontextmenü): Vorschau mit Richtung und Abstand je Methode („↑ 3“) und
//   den stehen bleibenden („bleibt: in einer Region“), dann ein
//   Rückgängig-Schritt und ein Eintrag in den Atlas-Änderungen.
// - editor.methodPlacement = off oder Atlas aus: kein Verschieben, der Befehl
//   meldet, dass er abgeschaltet ist.
// Gesichert über TAtlasFeature.MethodPlacement (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Editor.MethodPlacement;

type
  TAtlasMethodPlacementSessionFunc = reference to function: TLspSession;

  TAtlasIdeMethodPlacement = class
  private const
    /// <summary>Kurze Antwort beim Einfügen; das Ordnen der Unit darf länger dauern.</summary>
    cPlaceTimeoutMs = 3000;
    cArrangeTimeoutMs = 15000;
  private class var
    FInstance: TAtlasIdeMethodPlacement;
  private
    FSession: TAtlasMethodPlacementSessionFunc;
    FMessage: TProc<string>;
    FPolicy: TFunc<TAtlasUnopenedPolicy>;
    FTimer: TTimer;
    // Letzter Stand der aktiven Datei, gegen den neue Rümpfe zählen.
    FFileName: string;
    FText: string;
    FWriting: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Snapshot;
    procedure Place(const AView: IOTAEditView; const ABefore, AAfter: string);
    /// <summary>Schreibt AFinal (Stand nach dem Ordnen) in den Puffer von AView, möglichst als ein Schritt mit der
    /// Vervollständigung, und setzt den Cursor mit der verschobenen Methode.</summary>
    procedure WritePlaced(const AView: IOTAEditView; const ABefore, AAfter, AFinal: string;
      const AReply: TAtlasMethodPlacementReply);
    procedure Arrange;
    /// <summary>Übernimmt die Änderungen von AReply an AFileName und meldet das Ergebnis.</summary>
    procedure ApplyArranged(const AFileName: string; const AReply: TAtlasMethodPlacementReply);
    procedure Report(const AText: string);
    function CurrentSession: TLspSession;
    class function Mode: string; static;
    class function Texts: TAtlasMethodPlacementTexts; static;
    class procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string); static;
  public
    constructor Create(const ASession: TAtlasMethodPlacementSessionFunc; const AMessage: TProc<string>;
      const APolicy: TFunc<TAtlasUnopenedPolicy>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht, APolicy sagt, wie der Befehl nicht geöffnete Dateien behandelt.</summary>
    class procedure Install(const ASession: TAtlasMethodPlacementSessionFunc; const AMessage: TProc<string>;
      const APolicy: TFunc<TAtlasUnopenedPolicy>); static;
    class procedure Uninstall; static;
    /// <summary>editor.methodPlacement nicht off und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>„implementation wie Klasse ordnen“ (Befehl Atlas.MethodOrder).</summary>
    class procedure Run; static;
    /// <summary>Ansicht gewechselt: neuer Ausgangsstand beim nächsten Takt.</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: Zeitgeber neu starten.</summary>
    class procedure EditorModified; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.UI.Strings,
  Atlas.UI.Results.View,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit;

function IsPascal(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.inc');
end;

/// <summary>Aktive Ansicht einer Pascal-Datei; nil ohne.</summary>
function PascalView: IOTAEditView;
begin
  Result := TAtlasEditorBuffer.ActiveView;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsPascal(Result.Buffer.FileName)) then
  begin
    Result := nil;
  end;
end;

{ TAtlasIdeMethodPlacement }

constructor TAtlasIdeMethodPlacement.Create(const ASession: TAtlasMethodPlacementSessionFunc;
  const AMessage: TProc<string>; const APolicy: TFunc<TAtlasUnopenedPolicy>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FPolicy := APolicy;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasMethodPlacement.DelayMs;
  FTimer.OnTimer := TimerTick;
  Snapshot;
end;

destructor TAtlasIdeMethodPlacement.Destroy;
begin
  FreeAndNil(FTimer);
  FFileName := '';
  FText := '';
  inherited;
end;

class procedure TAtlasIdeMethodPlacement.Install(const ASession: TAtlasMethodPlacementSessionFunc;
  const AMessage: TProc<string>; const APolicy: TFunc<TAtlasUnopenedPolicy>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeMethodPlacement.Create(ASession, AMessage, APolicy);
  end;
end;

class procedure TAtlasIdeMethodPlacement.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeMethodPlacement.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and not SameText(mSettings.MethodPlacement, 'off');
end;

class function TAtlasIdeMethodPlacement.Mode: string;
begin
  Result := TAtlasIdeSettings.Current.MethodPlacement;
end;

class function TAtlasIdeMethodPlacement.Texts: TAtlasMethodPlacementTexts;
begin
  Result := Default(TAtlasMethodPlacementTexts);
  Result.Up := TAtlasStrings.Text(TAtlasTextId.MethodOrderUp);
  Result.Down := TAtlasStrings.Text(TAtlasTextId.MethodOrderDown);
  Result.Stays := TAtlasStrings.Text(TAtlasTextId.MethodOrderStays);
  Result.Region := TAtlasStrings.Text(TAtlasTextId.MethodOrderRegion);
  Result.Conditional := TAtlasStrings.Text(TAtlasTextId.MethodOrderConditional);
  Result.SharedLine := TAtlasStrings.Text(TAtlasTextId.MethodOrderSharedLine);
end;

class procedure TAtlasIdeMethodPlacement.Run;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  if not Enabled then
  begin
    FInstance.Report(TAtlasStrings.Text(TAtlasTextId.MethodOrderOff));
    Exit;
  end;
  FInstance.Arrange;
end;

class procedure TAtlasIdeMethodPlacement.Dismiss;
begin
  // Die neue Ansicht steht erst nach dem Wechsel fest: Der nächste Takt nimmt ihren Stand.
  if FInstance <> nil then
  begin
    FInstance.FFileName := '';
    FInstance.FText := '';
    FInstance.FTimer.Enabled := False;
    FInstance.FTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeMethodPlacement.EditorModified;
begin
  if (FInstance = nil) or FInstance.FWriting or not Enabled then
  begin
    Exit;
  end;
  FInstance.FTimer.Enabled := False;
  FInstance.FTimer.Enabled := True;
end;

procedure TAtlasIdeMethodPlacement.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeMethodPlacement.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
  begin
    Result := FSession();
  end;
end;

procedure TAtlasIdeMethodPlacement.Snapshot;
var
  mView: IOTAEditView;
begin
  FFileName := '';
  FText := '';
  mView := PascalView;
  if mView = nil then
  begin
    Exit;
  end;
  FFileName := mView.Buffer.FileName;
  FText := TAtlasEditorBuffer.Text(mView.Buffer);
end;

class procedure TAtlasIdeMethodPlacement.WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
var
  mRange: TLspTextRange;
  mWriter: IOTAEditWriter;
begin
  if not TAtlasMethodPlacement.Difference(AText, ANewText, mRange) then
  begin
    Exit;
  end;
  // Ein Schreiber = ein Rückgängig-Schritt.
  mWriter := ABuffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, mRange.StartOffset)));
  mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, mRange.EndOffset)));
  if mRange.NewText <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(mRange.NewText)));
  end;
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

procedure TAtlasIdeMethodPlacement.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.MethodPlacement,
    procedure
    var
      View: IOTAEditView;
      Text, Before: string;
    begin
      if not Enabled then
      begin
        Exit;
      end;
      View := PascalView;
      if View = nil then
      begin
        Exit;
      end;
      Text := TAtlasEditorBuffer.Text(View.Buffer);
      Before := FText;
      // Andere Datei als beim letzten Stand: erst der neue Ausgangsstand.
      if SameText(View.Buffer.FileName, FFileName) and TAtlasMethodPlacement.NewHeaders(Before, Text) then
      begin
        Place(View, Before, Text);
      end;
      Snapshot;
    end);
end;

/// <summary>Schickt AText von AFileName und fragt den Server mit AArguments; wirft ELspClientError.</summary>
function RequestPlacement(ASession: TLspSession; const AFileName, AText, AArguments: string; ATimeoutMs: Integer):
  TAtlasMethodPlacementReply;
var
  mAnswer: TJSONValue;
begin
  ASession.Sync(AFileName, AText);
  mAnswer := ASession.RunCommand(TAtlasMethodPlacement.Command, AArguments, ATimeoutMs);
  try
    TAtlasMethodPlacement.Read(mAnswer, Result);
  finally
    mAnswer.Free;
  end;
end;

/// <summary>Je verschobene Methode eine Zeile der Vorschau.</summary>
function PreviewOf(const AFileName: string; const AReply: TAtlasMethodPlacementReply;
  const ATexts: TAtlasMethodPlacementTexts): TArray<TAtlasResultEntry>;
var
  mMove: TAtlasMethodMove;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mMove in AReply.Moves do
  begin
    mEntry := TAtlasResultEntry.Create(AFileName, mMove.Line, 0);
    mEntry.Text := TAtlasMethodPlacement.MoveText(mMove, ATexts);
    Result := Result + [mEntry];
  end;
end;

procedure TAtlasIdeMethodPlacement.Place(const AView: IOTAEditView; const ABefore, AAfter: string);
var
  mSession: TLspSession;
  mFileName: string;
  mReply: TAtlasMethodPlacementReply;
begin
  mSession := CurrentSession;
  if mSession = nil then
  begin
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  try
    mReply := RequestPlacement(mSession, mFileName, AAfter, TAtlasMethodPlacement.Arguments(
      TLspSession.PathToUri(mFileName), Mode, False, ABefore), cPlaceTimeoutMs);
  except
    // Ohne Antwort bleibt der Rumpf, wo die IDE ihn hingesetzt hat.
    on ELspClientError do
    begin
      TAtlasGuard.Log('Methodenreihenfolge: keine Antwort des Servers');
      Exit;
    end;
  end;
  if (mReply.Edits <> nil) and (mReply.Moved > 0) then
  begin
    WritePlaced(AView, ABefore, AAfter, TLspEdits.Apply(AAfter, mReply.Edits), mReply);
  end;
end;

procedure TAtlasIdeMethodPlacement.WritePlaced(const AView: IOTAEditView; const ABefore, AAfter, AFinal: string;
  const AReply: TAtlasMethodPlacementReply);
var
  mBuffer: IOTAEditBuffer;
  mCaret: TOTAEditPos;
  mLine: Integer;
begin
  mBuffer := AView.Buffer;
  mCaret := AView.CursorPos;
  FWriting := True;
  try
    // Ein Schritt mit der Vervollständigung, wenn sich genau sie zurücknehmen lässt.
    if mBuffer.Undo and (TAtlasEditorBuffer.Text(mBuffer) = ABefore) then
    begin
      WriteBuffer(mBuffer, ABefore, AFinal);
    end
    else
    begin
      if TAtlasEditorBuffer.Text(mBuffer) <> AAfter then
      begin
        mBuffer.Redo;
      end;
      // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
      if TAtlasEditorBuffer.Text(mBuffer) <> AAfter then
      begin
        Exit;
      end;
      WriteBuffer(mBuffer, AAfter, AFinal);
    end;
    if TAtlasMethodPlacement.CaretLine(AReply.Moves, mCaret.Line - 1, mLine) then
    begin
      mCaret.Line := mLine + 1;
      AView.CursorPos := mCaret;
      AView.MoveViewToCursor;
    end;
    AView.Paint;
  finally
    FWriting := False;
  end;
end;

procedure TAtlasIdeMethodPlacement.Arrange;
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mFileName: string;
  mReply: TAtlasMethodPlacementReply;
  mOpen: TAtlasResultsOpen;
begin
  mView := PascalView;
  mSession := CurrentSession;
  if (mView <> nil) and (mSession = nil) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
  end;
  if (mView = nil) or (mSession = nil) then
  begin
    Exit;
  end;
  mFileName := mView.Buffer.FileName;
  try
    mReply := RequestPlacement(mSession, mFileName, TAtlasEditorBuffer.Text(mView.Buffer),
      TAtlasMethodPlacement.Arguments(TLspSession.PathToUri(mFileName), Mode, True, ''), cArrangeTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.MethodOrderFailed, [E.Message]));
      Exit;
    end;
  end;
  if (mReply.Edits = nil) or (mReply.Moved = 0) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MethodOrderNothing));
    Exit;
  end;
  mOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  if TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.MethodOrderTitle),
    TAtlasStrings.Fmt(TAtlasTextId.MethodOrderHint, [mReply.Moved, Length(mReply.Moves) - mReply.Moved]),
    TAtlasStrings.Text(TAtlasTextId.MethodOrderApply), TAtlasResults.Group(PreviewOf(mFileName, mReply, Texts)),
    mOpen) then
  begin
    ApplyArranged(mFileName, mReply);
  end;
end;

procedure TAtlasIdeMethodPlacement.ApplyArranged(const AFileName: string; const AReply: TAtlasMethodPlacementReply);
var
  mFiles: TLspFileEdits;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mFiles := Default(TLspFileEdits);
  mFiles.FileName := AFileName;
  mFiles.Edits := AReply.Edits;
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [mFiles];
  FWriting := True;
  try
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit, FPolicy(), TAtlasStrings.Text(TAtlasTextId.MethodOrderTitle));
  finally
    FWriting := False;
  end;
  Snapshot;
  if mOutcome.Error <> '' then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end
  else
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.MethodOrderDone, [AReply.Moved]));
  end;
end;

end.
