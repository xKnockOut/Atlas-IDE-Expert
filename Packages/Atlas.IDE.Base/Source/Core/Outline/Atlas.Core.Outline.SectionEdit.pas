unit Atlas.Core.Outline.SectionEdit;

// Neue Zeile am Ende eines Sichtbarkeitsabschnitts und fehlende Abschnitte
// anlegen (#1768), Kern ohne VCL und OTA. Abschnitte und Mitglieder aus
// TAtlasVisibilitySectionFinder.
// - Append fügt hinter der letzten Zeile des letzten Mitglieds des
//   Abschnitts eine leere Zeile ein, eingerückt wie das erste Mitglied;
//   Kommentare und Leerzeilen danach bleiben darunter. Ohne Mitglieder steht
//   die Zeile direkt unter dem Schlüsselwort (bzw. unter dem Typkopf), um
//   eine Ebene tiefer eingerückt.
// - Missing nennt die Abschnitte, die der Typ haben darf, aber nicht hat, in
//   der üblichen Reihenfolge (strict private, private, strict protected,
//   protected, public, published); Records kennen nur strict private,
//   private und public, Objekte kein strict.
// - Add setzt das Schlüsselwort vor den ersten vorhandenen Abschnitt, der in
//   der Reihenfolge danach kommt, sonst vor das end des Typs, mit einer neuen
//   eingerückten Zeile darunter.
// - Beide geben nur Zeilen zurück (Edit); den Puffer ändert die IDE. Steht
//   das Ende des Typs auf derselben Zeile wie das, wohinter eingefügt würde
//   (einzeiliger Typ), ändert sich nichts.

interface

uses
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.VisibilitySections;

type
  /// <summary>Einzufügende Zeilen und Cursor danach.</summary>
  TAtlasSectionEdit = record
    /// <summary>Zeile, vor der eingefügt wird, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Neue Zeilen ohne Zeilenende.</summary>
    Lines: TArray<string>;
    /// <summary>Cursor nach dem Einfügen, 0-basiert.</summary>
    CaretLine: Integer;
    CaretCharacter: Integer;
    /// <summary>ALines mit den neuen Zeilen.</summary>
    function Applied(const ALines: TArray<string>): TArray<string>;
  end;

  TAtlasSectionEditor = class
  public
    /// <summary>Neue Zeile am Ende des Abschnitts ASection (-1 = vor dem ersten Schlüsselwort) des Typs
    /// APlace.TypeNode; AIndentWidth ist eine Einrückungsebene. False, wenn nichts einzufügen geht.</summary>
    class function Append(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const APlace: TAtlasVisibilityPlace; ASection, AIndentWidth: Integer; out AEdit: TAtlasSectionEdit): Boolean;
      static;
    /// <summary>Abschnitte, die der Typ APlace.TypeNode haben darf und nicht hat, in der üblichen
    /// Reihenfolge.</summary>
    class function Missing(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasVisibilityPlace): TArray<string>;
      static;
    /// <summary>Abschnitt AKeyword im Typ APlace.TypeNode anlegen, mit eingerückter Zeile darunter.</summary>
    class function Add(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const APlace: TAtlasVisibilityPlace; const AKeyword: string; AIndentWidth: Integer;
      out AEdit: TAtlasSectionEdit): Boolean; static;
    /// <summary>Rang in der üblichen Reihenfolge, 0 = strict private; -1 bei unbekanntem Wort.</summary>
    class function Rank(const AKeyword: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines;

const
  cOrder: array[0..5] of string = ('strict private', 'private', 'strict protected', 'protected', 'public',
    'published');

function TAtlasSectionEdit.Applied(const ALines: TArray<string>): TArray<string>;
begin
  Result := Copy(ALines, 0, Line) + Lines + Copy(ALines, Line, Length(ALines) - Line);
end;

/// <summary>Leerraum am Anfang der Zeile ALine; '' außerhalb.</summary>
function LineIndent(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    Result := TTextLines.IndentOf(ALines[ALine]);
  end;
end;

/// <summary>Steht vor ACharacter in der Zeile nur Leerraum?</summary>
function StartsLine(const ALines: TArray<string>; ALine, ACharacter: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine <= High(ALines)) and (Trim(Copy(ALines[ALine], 1, ACharacter)) = '');
end;

function NewEdit(ALine: Integer; const ALines: TArray<string>; ACaretOffset: Integer): TAtlasSectionEdit;
begin
  Result.Line := ALine;
  Result.Lines := ALines;
  Result.CaretLine := ALine + ACaretOffset;
  Result.CaretCharacter := Length(ALines[ACaretOffset]);
end;

/// <summary>Letzte Zeile der Mitglieder AMembers; -1 ohne.</summary>
function LastLineOf(const ANodes: TAtlasOutlineNodes; const AMembers: TArray<Integer>): Integer;
var
  mMember: Integer;
begin
  Result := -1;
  for mMember in AMembers do
  begin
    if ANodes[mMember].EndLine > Result then
    begin
      Result := ANodes[mMember].EndLine;
    end;
  end;
end;

/// <summary>Einrückung der Mitglieder des Typs: wie das erste Mitglied in irgendeinem Abschnitt; '' ohne.</summary>
function MemberIndent(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AType: Integer;
  out AIndent: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Parent = AType) and not ANodes[mIndex].Hidden and
      StartsLine(ALines, ANodes[mIndex].StartLine, ANodes[mIndex].StartCharacter) then
    begin
      AIndent := LineIndent(ALines, ANodes[mIndex].StartLine);
      Exit(True);
    end;
  end;
  AIndent := '';
  Result := False;
end;

class function TAtlasSectionEditor.Rank(const AKeyword: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cOrder) do
  begin
    if SameText(cOrder[mIndex], AKeyword) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasSectionEditor.Append(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const APlace: TAtlasVisibilityPlace; ASection, AIndentWidth: Integer; out AEdit: TAtlasSectionEdit): Boolean;
var
  mType: TAtlasOutlineNode;
  mMembers: TArray<Integer>;
  mAnchor: Integer;
  mIndent: string;
begin
  Result := False;
  AEdit := Default(TAtlasSectionEdit);
  if (APlace.TypeNode < 0) or (APlace.TypeNode > High(ANodes)) or (ASection < -1) or
    (ASection > High(APlace.Sections)) then
  begin
    Exit;
  end;
  mType := ANodes[APlace.TypeNode];
  mMembers := TAtlasVisibilitySectionFinder.MembersOf(ANodes, APlace, ASection);
  if Length(mMembers) > 0 then
  begin
    mAnchor := LastLineOf(ANodes, mMembers);
    mIndent := LineIndent(ALines, ANodes[mMembers[0]].StartLine);
  end
  else
  begin
    if ASection >= 0 then
    begin
      mAnchor := APlace.Sections[ASection].Line;
    end
    else
    begin
      mAnchor := mType.NameLine;
    end;
    mIndent := LineIndent(ALines, mAnchor) + StringOfChar(' ', AIndentWidth);
  end;
  // Einzeiliger Typ: Hinter der Zeile stünde das end schon.
  if (mAnchor < 0) or (mAnchor >= mType.EndLine) then
  begin
    Exit;
  end;
  AEdit := NewEdit(mAnchor + 1, [mIndent], 0);
  Result := True;
end;

/// <summary>Darf ein Typ der Art ADetail den Abschnitt AKeyword haben?</summary>
function Allowed(const ADetail, AKeyword: string): Boolean;
begin
  if SameText(ADetail, 'record') then
  begin
    Result := SameText(AKeyword, 'strict private') or SameText(AKeyword, 'private') or SameText(AKeyword, 'public');
  end
  else if SameText(ADetail, 'object') then
  begin
    Result := not AKeyword.StartsWith('strict');
  end
  else
  begin
    Result := True;
  end;
end;

function HasSection(const APlace: TAtlasVisibilityPlace; const AKeyword: string): Boolean;
var
  mSection: TAtlasVisibilitySection;
begin
  for mSection in APlace.Sections do
  begin
    if SameText(mSection.Keyword, AKeyword) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSectionEditor.Missing(const ANodes: TAtlasOutlineNodes;
  const APlace: TAtlasVisibilityPlace): TArray<string>;
var
  mKeyword: string;
begin
  Result := nil;
  if (APlace.TypeNode < 0) or (APlace.TypeNode > High(ANodes)) then
  begin
    Exit;
  end;
  for mKeyword in cOrder do
  begin
    if Allowed(ANodes[APlace.TypeNode].Detail, mKeyword) and not HasSection(APlace, mKeyword) then
    begin
      Result := Result + [mKeyword];
    end;
  end;
end;

/// <summary>Erster Abschnitt, der in der Reihenfolge hinter ARank kommt; -1 ohne.</summary>
function NextSection(const APlace: TAtlasVisibilityPlace; ARank: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(APlace.Sections) do
  begin
    if TAtlasSectionEditor.Rank(APlace.Sections[mIndex].Keyword) > ARank then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Steht das end des Typs am Anfang seiner Zeile (nicht hinter Mitgliedern)?</summary>
function EndStartsLine(const ALines: TArray<string>; const AType: TAtlasOutlineNode): Boolean;
var
  mText: string;
begin
  Result := (AType.EndLine > AType.NameLine) and (AType.EndLine <= High(ALines));
  if Result then
  begin
    mText := LowerCase(TrimLeft(ALines[AType.EndLine]));
    Result := mText.StartsWith('end') and ((Length(mText) = 3) or not CharInSet(mText[4], ['a'..'z', '0'..'9',
      '_']));
  end;
end;

class function TAtlasSectionEditor.Add(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const APlace: TAtlasVisibilityPlace; const AKeyword: string; AIndentWidth: Integer;
  out AEdit: TAtlasSectionEdit): Boolean;
var
  mType: TAtlasOutlineNode;
  mNext, mLine: Integer;
  mKeywordIndent, mIndent: string;
begin
  Result := False;
  AEdit := Default(TAtlasSectionEdit);
  if (APlace.TypeNode < 0) or (APlace.TypeNode > High(ANodes)) or (Rank(AKeyword) < 0) or
    HasSection(APlace, AKeyword) then
  begin
    Exit;
  end;
  mType := ANodes[APlace.TypeNode];
  mNext := NextSection(APlace, Rank(AKeyword));
  if mNext >= 0 then
  begin
    mLine := APlace.Sections[mNext].Line;
    if not StartsLine(ALines, mLine, APlace.Sections[mNext].Character) then
    begin
      Exit;
    end;
  end
  else
  begin
    mLine := mType.EndLine;
    if not EndStartsLine(ALines, mType) then
    begin
      Exit;
    end;
  end;
  // Schlüsselwörter wie die vorhandenen, sonst wie das end des Typs.
  if Length(APlace.Sections) > 0 then
  begin
    mKeywordIndent := LineIndent(ALines, APlace.Sections[0].Line);
  end
  else
  begin
    mKeywordIndent := LineIndent(ALines, mType.EndLine);
  end;
  if not MemberIndent(ANodes, ALines, APlace.TypeNode, mIndent) then
  begin
    mIndent := mKeywordIndent + StringOfChar(' ', AIndentWidth);
  end;
  AEdit := NewEdit(mLine, [mKeywordIndent + AKeyword, mIndent], 1);
  Result := True;
end;

end.
