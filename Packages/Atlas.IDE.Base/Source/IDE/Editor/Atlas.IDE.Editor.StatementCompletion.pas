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
    class function Followed(const AFileName, ANewText, ALineBreak: string; const AEdit: TAtlasStatementEdit;
      var ACursorLine, ACursorCharacter: Integer): string; static;
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
  begin
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  end;
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function LineCount(const AText: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

type
  /// <summary>Code-Aktion mit Tag an Position für Text (dem Server vorher geschickt) in FileName; Zeilenumbrüche
  /// wie LineBreak.</summary>
  TActionRequest = record
    FileName: string;
    Text: string;
    LineBreak: string;
    Tag: string;
    Position: TLspTextPosition;
  end;

/// <summary>Änderungen der ersten nutzbaren Code-Aktion von ARequest in ihrer Datei; False ohne.</summary>
function ActionEdits(const ASession: TLspSession; const ARequest: TActionRequest;
  out AEdits: TArray<TLspTextEdit>): Boolean;
var
  mAction: TLspCodeAction;
  mFiles: TLspFileEdits;
begin
  AEdits := nil;
  ASession.Sync(ARequest.FileName, ARequest.Text);
  for mAction in ASession.CodeActions(ARequest.FileName, TLspRange.Create(ARequest.Position.Line,
    ARequest.Position.Character, ARequest.Position.Line, ARequest.Position.Character)) do
  begin
    if SameText(mAction.Tag, ARequest.Tag) and (mAction.Disabled = '') then
    begin
      for mFiles in mAction.Edit.Files do
      begin
        if SameText(mFiles.FileName, ARequest.FileName) then
        begin
          AEdits := AEdits + mFiles.Edits;
        end;
      end;
      Break;
    end;
  end;
  Result := Length(AEdits) > 0;
end;

/// <summary>Code-Aktion von ARequest angewandt; False ohne Aktion. ACursorLine verschiebt sich um die Zeilen, die
/// vor ihr dazukommen.</summary>
function WithServerAction(const ASession: TLspSession; const ARequest: TActionRequest; var ACursorLine: Integer;
  out AResult: string): Boolean;
var
  mEdits: TArray<TLspTextEdit>;
  mIndex, mShift: Integer;
begin
  AResult := ARequest.Text;
  Result := ActionEdits(ASession, ARequest, mEdits);
  if not Result then
  begin
    Exit;
  end;
  mShift := 0;
  for mIndex := 0 to High(mEdits) do
  begin
    // Zeilenumbrüche wie im Puffer.
    mEdits[mIndex].NewText := StringReplace(StringReplace(mEdits[mIndex].NewText, #13#10, #10, [rfReplaceAll]),
      #10, ARequest.LineBreak, [rfReplaceAll]);
    if mEdits[mIndex].EndPos.Line < ACursorLine then
    begin
      Inc(mShift, LineCount(mEdits[mIndex].NewText) - (mEdits[mIndex].EndPos.Line - mEdits[mIndex].StartPos.Line));
    end;
  end;
  AResult := TLspEdits.Apply(ARequest.Text, mEdits);
  Inc(ACursorLine, mShift);
end;

/// <summary>Kennung der Code-Aktion, die AFollowUp nachliefert ('' ohne).</summary>
function FollowUpTag(AFollowUp: TAtlasStatementFollowUp): string;
begin
  Result := '';
  if AFollowUp = TAtlasStatementFollowUp.MethodBody then
  begin
    Result := ClassBodiesTag;
  end
  else if AFollowUp = TAtlasStatementFollowUp.CaseBranches then
  begin
    Result := CaseCompleteTag;
  end;
end;

/// <summary>Fläche, über der die Auswahl erscheint: aktives Formular, Hauptfenster oder Arbeitsfläche.</summary>
function PaletteArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

/// <summary>Gerüst nach try erfragen und damit vervollständigen.</summary>
procedure ChooseTryKind;
var
  mCommands: TArray<TAtlasCommand>;
  mCommand: TAtlasCommand;
  mWindow: TAtlasPaletteWindow;
begin
  mCommand := Default(TAtlasCommand);
  mCommand.Id := 'finally';
  mCommand.Caption := TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryFinally);
  mCommands := [mCommand];
  mCommand.Id := 'except';
  mCommand.Caption := TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryExcept);
  mCommands := mCommands + [mCommand];
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, mCommands, nil, TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.OnExecute :=
    procedure(AChosen: TAtlasCommand)
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          if AChosen.Id = 'except' then
          begin
            TAtlasIdeStatementCompletion.RunWith(TAtlasTryKind.TryExcept);
          end
          else
          begin
            TAtlasIdeStatementCompletion.RunWith(TAtlasTryKind.TryFinally);
          end;
        end);
    end;
  mWindow.ShowOver(PaletteArea);
end;

/// <summary>Cursor auf Zeile ALine (ab 0), Zeichen ACharacter in ALines; nichts, wenn es die Zeile nicht gibt.
/// </summary>
procedure PlaceCursor(const AView: IOTAEditView; const ALines: TArray<string>; ALine, ACharacter,
  ATabWidth: Integer);
var
  mTarget: TOTAEditPos;
begin
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit;
  end;
  mTarget.Line := ALine + 1;
  mTarget.Col := TLspSession.IndexToColumn(ALines[ALine], ACharacter, ATabWidth);
  AView.CursorPos := mTarget;
  AView.MoveViewToCursor;
  AView.Paint;
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
  begin
    Result.BeginEnd := TAtlasBeginEndMode.Always;
  end
  else if TAtlasIdeSettings.Current.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndNever then
  begin
    Result.BeginEnd := TAtlasBeginEndMode.Never;
  end;
  Result.TryKind := ATryKind;
  Result.IndentWidth := AIndentWidth;
  Result.MethodBody := TAtlasIdeSettings.Current.CompleteStatementMethodBody;
end;

class procedure TAtlasIdeStatementCompletion.Run;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if not Enabled or (mView = nil) or (mView.Buffer = nil) or mView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  if TAtlasIdeSettings.Current.CompleteStatementTryKind = TAtlasPluginSettings.TryKindExcept then
  begin
    RunWith(TAtlasTryKind.TryExcept);
  end
  else if (TAtlasIdeSettings.Current.CompleteStatementTryKind <> TAtlasPluginSettings.TryKindAsk) or
    not TAtlasStatementCompleter.NeedsTryKind(TAtlasEditorBuffer.Text(mView.Buffer), mView.CursorPos.Line - 1) then
  begin
    RunWith(TAtlasTryKind.TryFinally);
  end
  else
  begin
    ChooseTryKind;
  end;
end;

/// <summary>Rumpf bzw. Zweige vom Server, auf den ergänzten Text ANewText; ohne Server oder Antwort bleibt es beim
/// Gerüst.</summary>
class function TAtlasIdeStatementCompletion.Followed(const AFileName, ANewText, ALineBreak: string;
  const AEdit: TAtlasStatementEdit; var ACursorLine, ACursorCharacter: Integer): string;
var
  mRequest: TActionRequest;
  mSession: TLspSession;
  mLines: TArray<string>;
begin
  Result := ANewText;
  mRequest.FileName := AFileName;
  mRequest.Text := ANewText;
  mRequest.LineBreak := ALineBreak;
  mRequest.Tag := FollowUpTag(AEdit.FollowUp);
  mRequest.Position := TLspTextPosition.Create(AEdit.FollowLine, AEdit.FollowCharacter);
  mSession := nil;
  if (mRequest.Tag <> '') and Assigned(FSessionOf) then
  begin
    mSession := FSessionOf();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  try
    if WithServerAction(mSession, mRequest, ACursorLine, Result) and
      (AEdit.FollowUp = TAtlasStatementFollowUp.CaseBranches) then
    begin
      mLines := Result.Split([#13#10, #10]);
      if TAtlasStatementCompleter.AfterCaseBranches(mLines, ACursorLine, ACursorCharacter) then
      begin
        Result := string.Join(ALineBreak, mLines);
      end;
    end;
  except
    on E: ELspClientError do
      if Assigned(FMessage) then
      begin
        FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      end;
    on E: ELspEditError do
      if Assigned(FMessage) then
      begin
        FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      end;
  end;
end;

class procedure TAtlasIdeStatementCompletion.RunWith(ATryKind: TAtlasTryKind);
var
  mView: IOTAEditView;
  mText, mLineBreak, mFinal, mInsert: string;
  mEdit: TAtlasStatementEdit;
  mCursorLine, mCursorCharacter, mStart, mOldLength: Integer;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if not Enabled or (mView = nil) or (mView.Buffer = nil) or mView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLineBreak := #10;
  if Pos(#13#10, mText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  if not TAtlasStatementCompleter.Complete(mText, mView.CursorPos.Line - 1,
    Options(TAtlasEditorBuffer.BlockIndent(mView.Buffer), ATryKind), mEdit) then
  begin
    Exit;
  end;
  mCursorLine := mEdit.CursorLine;
  mCursorCharacter := mEdit.CursorCharacter;
  mFinal := Followed(mView.Buffer.FileName, string.Join(mLineBreak,
    TAtlasStatementCompleter.Apply(mText.Split([#13#10, #10]), mEdit)), mLineBreak, mEdit, mCursorLine,
    mCursorCharacter);
  if TAtlasLineMover.Difference(mText, mFinal, mStart, mOldLength, mInsert) then
  begin
    WriteBuffer(mView.Buffer, mText, mStart, mOldLength, mInsert);
  end;
  PlaceCursor(mView, mFinal.Split([#13#10, #10]), mCursorLine, mCursorCharacter,
    TAtlasEditorBuffer.TabWidth(mView.Buffer));
end;

end.
