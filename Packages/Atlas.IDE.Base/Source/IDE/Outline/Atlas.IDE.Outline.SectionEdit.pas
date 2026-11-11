unit Atlas.IDE.Outline.SectionEdit;

// „Neue Zeile am Ende von …“ und „Abschnitt anlegen“ im Editor (#1768). Was
// eingefügt wird, rechnet TAtlasSectionEditor aus der Gliederung
// (TAtlasIdeOutlineCache); hier bleiben Puffer und Cursor.
// - Eine Änderung ist ein Schreiber der IDE (CreateUndoableWriter), also ein
//   Rückgängig-Schritt; Einrückungsebene ist der Blockeinzug der IDE.
// - Geändert wird nur, wenn der Puffer noch genau den Text hat, zu dem die
//   Gliederung gehört; sonst (gerade getippt, Gliederung noch nicht neu)
//   bleibt der Puffer unverändert und das Protokoll sagt es.
// - AppendAtCursor (Befehlspalette, keys.sectionAppend) nimmt den Abschnitt
//   am Cursor, Append und Add die Auswahl im Sprungmenü des
//   Sichtbarkeitsglieds.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Outline.Model;

type
  TAtlasIdeSectionEdit = class
  public
    /// <summary>editor.breadcrumbs und editor.breadcrumbsSectionAppend an (Palette, Taste)?</summary>
    class function AppendEnabled: Boolean; static;
    /// <summary>Neue Zeile am Ende des Abschnitts am Cursor im oberen Editor.</summary>
    class procedure AppendAtCursor; static;
    /// <summary>Neue Zeile am Ende des Abschnitts ASection (-1 = vor dem ersten Schlüsselwort) des Typs um
    /// ALine/ACharacter in AFileName; ANodes und ALines sind der Stand, aus dem das Menü stammt.</summary>
    class procedure Append(const AFileName: string; const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ALine, ACharacter, ASection: Integer); static;
    /// <summary>Abschnitt AKeyword im Typ um ALine/ACharacter in AFileName anlegen.</summary>
    class procedure Add(const AFileName: string; const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ALine, ACharacter: Integer; const AKeyword: string); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Outline.VisibilitySections,
  Atlas.Core.Outline.SectionEdit,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Outline.Cache;

type
  /// <summary>Rechnet die Änderung für Typ und Abschnitt am Ort; False = nichts zu tun.</summary>
  TEditOf = reference to function(const APlace: TAtlasVisibilityPlace; AIndentWidth: Integer;
    out AEdit: TAtlasSectionEdit): Boolean;

function SameLines(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := A[mIndex] = B[mIndex];
    Inc(mIndex);
  end;
end;

/// <summary>Änderung AEditOf am Typ um ALine/ACharacter im Puffer von AFileName ausführen und den Cursor
/// setzen.</summary>
procedure Run(const AFileName: string; const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ALine, ACharacter: Integer; const AEditOf: TEditOf);
var
  mView: IOTAEditView;
  mBuffer: IOTAEditBuffer;
  mText, mLineBreak, mInsert: string;
  mLines, mNewLines: TArray<string>;
  mPlace: TAtlasVisibilityPlace;
  mEdit: TAtlasSectionEdit;
  mStart, mOldLength: Integer;
  mCursor: TOTAEditPos;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) or
    mView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  mBuffer := mView.Buffer;
  mText := TAtlasEditorBuffer.Text(mBuffer);
  mLines := TTextLines.SplitLines(mText, mLineBreak);
  if not SameLines(mLines, ALines) then
  begin
    TAtlasGuard.Log('Section edit: outline no longer matches the buffer, nothing changed');
    Exit;
  end;
  mPlace := TAtlasVisibilitySectionFinder.At(ANodes, ALines, ALine, ACharacter);
  if (mPlace.TypeNode < 0) or not AEditOf(mPlace, TAtlasEditorBuffer.BlockIndent(mBuffer), mEdit) then
  begin
    TAtlasGuard.Log('Section edit: no type with sections or nothing to insert');
    Exit;
  end;
  mNewLines := mEdit.Applied(mLines);
  if TAtlasLineMover.Difference(mText, string.Join(mLineBreak, mNewLines), mStart, mOldLength, mInsert) then
  begin
    TAtlasEditorSnapshots.ReplaceText(mBuffer, mText, mStart, mOldLength, mInsert);
  end;
  mCursor.Line := mEdit.CaretLine + 1;
  mCursor.Col := TLspSession.IndexToColumn(mNewLines[mEdit.CaretLine], mEdit.CaretCharacter,
    TAtlasEditorBuffer.TabWidth(mBuffer));
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

{ TAtlasIdeSectionEdit }

class function TAtlasIdeSectionEdit.AppendEnabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Breadcrumbs and TAtlasIdeSettings.Current.BreadcrumbsSectionAppend;
end;

class procedure TAtlasIdeSectionEdit.Append(const AFileName: string; const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>; ALine, ACharacter, ASection: Integer);
begin
  Run(AFileName, ANodes, ALines, ALine, ACharacter,
    function(const APlace: TAtlasVisibilityPlace; AIndentWidth: Integer; out AEdit: TAtlasSectionEdit): Boolean
    begin
      Result := TAtlasSectionEditor.Append(ANodes, ALines, APlace, ASection, AIndentWidth, AEdit);
    end);
end;

class procedure TAtlasIdeSectionEdit.Add(const AFileName: string; const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>; ALine, ACharacter: Integer; const AKeyword: string);
begin
  Run(AFileName, ANodes, ALines, ALine, ACharacter,
    function(const APlace: TAtlasVisibilityPlace; AIndentWidth: Integer; out AEdit: TAtlasSectionEdit): Boolean
    begin
      Result := TAtlasSectionEditor.Add(ANodes, ALines, APlace, AKeyword, AIndentWidth, AEdit);
    end);
end;

class procedure TAtlasIdeSectionEdit.AppendAtCursor;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mLines: TArray<string>;
  mNodes: TAtlasOutlineNodes;
  mLine, mCharacter: Integer;
begin
  if not AppendEnabled then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  if (mSnapshot.Status <> TAtlasOutlineStatus.Ready) or (mView.CursorPos.Line < 1) then
  begin
    TAtlasGuard.Log('Section edit: no outline for the active file');
    Exit;
  end;
  mLines := TTextLines.SplitLines(mSnapshot.Text);
  mNodes := mSnapshot.Nodes;
  mLine := mView.CursorPos.Line - 1;
  mCharacter := 0;
  if mLine <= High(mLines) then
  begin
    mCharacter := TLspSession.ColumnToIndex(mLines[mLine], mView.CursorPos.Col,
      TAtlasEditorBuffer.TabWidth(mView.Buffer));
  end;
  Run(mSnapshot.FileName, mNodes, mLines, mLine, mCharacter,
    function(const APlace: TAtlasVisibilityPlace; AIndentWidth: Integer; out AEdit: TAtlasSectionEdit): Boolean
    begin
      Result := TAtlasSectionEditor.Append(mNodes, mLines, APlace, APlace.Current, AIndentWidth, AEdit);
    end);
end;

end.
