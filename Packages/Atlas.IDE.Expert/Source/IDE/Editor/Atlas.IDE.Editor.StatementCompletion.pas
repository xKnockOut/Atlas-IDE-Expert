unit Atlas.IDE.Editor.StatementCompletion;

// Anweisung vervollständigen (#697) im Editor: Strg+Umschalt+Enter. Was
// fehlt, rechnet Atlas.Core.Editor.StatementCompletion aus; hier bleiben
// Puffer, Server und Cursor.
// - Methodenrumpf und case-Zweige kommen vom Server (Code-Aktionen mit den
//   Kennungen class.bodies bzw. case.complete). Atlas schickt ihm dafür den
//   ergänzten Text, holt die Aktion, wendet ihre Änderungen auf diesen Text an
//   und schreibt erst dann, mit einem Schreiber (CreateUndoableWriter): Alles
//   ist ein Rückgängig-Schritt. Ohne Server oder Aktion bleibt es beim Gerüst.
// - tryKind "ask": Vor einem try ohne finally/except fragt eine kleine
//   Auswahl, welches Gerüst es sein soll.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.StatementCompletion;

type
  TAtlasIdeStatementCompletion = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
  private
    class procedure RunWith(ATryKind: TAtlasTryKind); static;
  public
    /// <summary>ASessionOf: laufende Sitzung oder nil; AMessage zeigt eine Zeile in der Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>editor.completeStatement an (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Vervollständigt die Anweisung am Cursor im oberen Editor.</summary>
    class procedure Run; static;
    /// <summary>Optionen aus den Einstellungen; AIndentWidth ist der Blockeinzug der IDE.</summary>
    class function Options(AIndentWidth: Integer; ATryKind: TAtlasTryKind): TAtlasStatementOptions; static;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Editor.LineMove,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorSnapshot;

const
  // Wie ClassBodiesTag und CaseCompleteTag des Servers (Atlas.Common.Editing.CodeActions).
  ClassBodiesTag = 'class.bodies';
  CaseCompleteTag = 'case.complete';

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein
/// Rückgängig-Schritt.</summary>
procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
  const AInsert: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function LineCount(const AText: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
      Inc(Result);
end;

/// <summary>Code-Aktion mit ATag an ALine, ACharacter für AText (dem Server vorher geschickt) angewandt; False
/// ohne Aktion. ACursorLine verschiebt sich um die Zeilen, die vor ihr dazukommen.</summary>
function WithServerAction(const ASession: TLspSession; const AFileName, AText, ALineBreak, ATag: string;
  ALine, ACharacter: Integer; var ACursorLine: Integer; out AResult: string): Boolean;
var
  Actions: TArray<TLspCodeAction>;
  Action: TLspCodeAction;
  Files: TLspFileEdits;
  Edits: TArray<TLspTextEdit>;
  Index, Shift: Integer;
begin
  Result := False;
  AResult := AText;
  ASession.Sync(AFileName, AText);
  Actions := ASession.CodeActions(AFileName, TLspRange.Create(ALine, ACharacter, ALine, ACharacter));
  for Action in Actions do
    if SameText(Action.Tag, ATag) and (Action.Disabled = '') then
    begin
      Edits := nil;
      for Files in Action.Edit.Files do
        if SameText(Files.FileName, AFileName) then
          Edits := Edits + Files.Edits;
      if Length(Edits) = 0 then
        Exit;
      Shift := 0;
      for Index := 0 to High(Edits) do
      begin
        // Zeilenumbrüche wie im Puffer.
        Edits[Index].NewText := StringReplace(StringReplace(Edits[Index].NewText, #13#10, #10, [rfReplaceAll]),
          #10, ALineBreak, [rfReplaceAll]);
        if Edits[Index].EndPos.Line < ACursorLine then
          Inc(Shift, LineCount(Edits[Index].NewText) - (Edits[Index].EndPos.Line - Edits[Index].StartPos.Line));
      end;
      AResult := TLspEdits.Apply(AText, Edits);
      Inc(ACursorLine, Shift);
      Exit(True);
    end;
end;

{ TAtlasIdeStatementCompletion }

class procedure TAtlasIdeStatementCompletion.Install(const ASessionOf: TFunc<TLspSession>;
  const AMessage: TProc<string>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
end;

class procedure TAtlasIdeStatementCompletion.Uninstall;
begin
  FSessionOf := nil;
  FMessage := nil;
end;

class function TAtlasIdeStatementCompletion.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.CompleteStatement;
end;

class function TAtlasIdeStatementCompletion.Options(AIndentWidth: Integer;
  ATryKind: TAtlasTryKind): TAtlasStatementOptions;
begin
  Result := TAtlasStatementOptions.Defaults;
  if TAtlasIdeSettings.Current.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndAlways then
    Result.BeginEnd := TAtlasBeginEndMode.Always
  else if TAtlasIdeSettings.Current.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndNever then
    Result.BeginEnd := TAtlasBeginEndMode.Never;
  Result.TryKind := ATryKind;
  Result.IndentWidth := AIndentWidth;
  Result.MethodBody := TAtlasIdeSettings.Current.CompleteStatementMethodBody;
end;

class procedure TAtlasIdeStatementCompletion.Run;
var
  View: IOTAEditView;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  if not Enabled then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or View.Buffer.IsReadOnly then
    Exit;
  if TAtlasIdeSettings.Current.CompleteStatementTryKind = TAtlasPluginSettings.TryKindExcept then
  begin
    RunWith(TAtlasTryKind.TryExcept);
    Exit;
  end;
  if (TAtlasIdeSettings.Current.CompleteStatementTryKind <> TAtlasPluginSettings.TryKindAsk) or
    not TAtlasStatementCompleter.NeedsTryKind(TAtlasEditorBuffer.Text(View.Buffer), View.CursorPos.Line - 1) then
  begin
    RunWith(TAtlasTryKind.TryFinally);
    Exit;
  end;
  // Gerüst nach try erfragen.
  Command := Default(TAtlasCommand);
  Command.Id := 'finally';
  Command.Caption := TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryFinally);
  Commands := [Command];
  Command.Id := 'except';
  Command.Caption := TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryExcept);
  Commands := Commands + [Command];
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(AChosen: TAtlasCommand)
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          if AChosen.Id = 'except' then
            RunWith(TAtlasTryKind.TryExcept)
          else
            RunWith(TAtlasTryKind.TryFinally);
        end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class procedure TAtlasIdeStatementCompletion.RunWith(ATryKind: TAtlasTryKind);
var
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Session: TLspSession;
  Text, LineBreak, NewText, Final, Insert, Tag: string;
  Lines, NewLines: TArray<string>;
  Edit: TAtlasStatementEdit;
  TabWidth, CursorLine, CursorCharacter, Start, OldLength: Integer;
  Target: TOTAEditPos;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if not Enabled or (View = nil) or (View.Buffer = nil) then
    Exit;
  Buffer := View.Buffer;
  if Buffer.IsReadOnly then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
    LineBreak := #13#10;
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(Buffer);
  if not TAtlasStatementCompleter.Complete(Text, View.CursorPos.Line - 1,
    Options(TAtlasEditorBuffer.BlockIndent(Buffer), ATryKind), Edit) then
    Exit;
  NewLines := TAtlasStatementCompleter.Apply(Lines, Edit);
  NewText := string.Join(LineBreak, NewLines);
  Final := NewText;
  CursorLine := Edit.CursorLine;
  CursorCharacter := Edit.CursorCharacter;
  // Rumpf bzw. Zweige vom Server, auf den ergänzten Text.
  Tag := '';
  if Edit.FollowUp = TAtlasStatementFollowUp.MethodBody then
    Tag := ClassBodiesTag
  else if Edit.FollowUp = TAtlasStatementFollowUp.CaseBranches then
    Tag := CaseCompleteTag;
  Session := nil;
  if (Tag <> '') and Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session <> nil then
    try
      if WithServerAction(Session, Buffer.FileName, NewText, LineBreak, Tag, Edit.FollowLine,
        Edit.FollowCharacter, CursorLine, Final) and (Edit.FollowUp = TAtlasStatementFollowUp.CaseBranches) then
      begin
        NewLines := Final.Split([#13#10, #10]);
        if TAtlasStatementCompleter.AfterCaseBranches(NewLines, CursorLine, CursorCharacter) then
          Final := string.Join(LineBreak, NewLines);
      end;
    except
      // Ohne Antwort bleibt es beim Gerüst.
      on E: ELspClientError do
        if Assigned(FMessage) then
          FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      on E: ELspEditError do
        if Assigned(FMessage) then
          FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
    end;
  NewLines := Final.Split([#13#10, #10]);
  if TAtlasLineMover.Difference(Text, Final, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  if (CursorLine < 0) or (CursorLine > High(NewLines)) then
    Exit;
  Target.Line := CursorLine + 1;
  Target.Col := TLspSession.IndexToColumn(NewLines[CursorLine], CursorCharacter, TabWidth);
  View.CursorPos := Target;
  View.MoveViewToCursor;
  View.Paint;
end;

end.
