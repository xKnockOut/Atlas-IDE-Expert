unit Atlas.Core.Outline.VisibilitySections;

// Sichtbarkeitsabschnitte im Deklarationsteil eines Typs (#1759), Kern ohne
// VCL und OTA:
// - At findet den innersten Typ mit Abschnitten (class, record, object,
//   Helfer) am Caret und den Abschnitt, in dem der Caret steht: das letzte
//   Schlüsselwort (strict private, private, strict protected, protected,
//   public, published) bis zur Zeile des Carets. Es zählt der Text, nicht der
//   Knoten unter dem Caret, damit auch Leerzeilen, Kommentare und eben
//   getippte Zeilen zwischen den Mitgliedern ihren Abschnitt haben.
// - Verschachtelte Typen haben ihre eigenen Abschnitte; ihr Text zählt für den
//   äußeren Typ nicht. Kommentare, Strings und Direktiven zählen nie.
// - Vor dem ersten Schlüsselwort gilt die implizite Sichtbarkeit: published
//   bei Klassen unter {$M+} bzw. {$TYPEINFO ON} und bei Klassen, die (auch
//   über Vorfahren in derselben Unit) von einer bekannten TPersistent-Klasse
//   erben; sonst public.
// - Vorwärtsdeklarationen (TFoo = class;) haben keine Abschnitte. Auf der
//   Kopfzeile eines verschachtelten Typs gilt der Abschnitt des umgebenden.

interface

uses
  Atlas.Core.Outline.Model;

type
  /// <summary>Ein Sichtbarkeitsschlüsselwort im Deklarationsteil eines Typs.</summary>
  TAtlasVisibilitySection = record
    /// <summary>Schlüsselwort klein, bei strict mit einem Leerzeichen („strict private“).</summary>
    Keyword: string;
    /// <summary>Anfang des Schlüsselworts (bei strict das Wort strict), 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  TAtlasVisibilitySections = TArray<TAtlasVisibilitySection>;

  /// <summary>Abschnitt an einer Stelle des Quelltexts.</summary>
  TAtlasVisibilityPlace = record
    /// <summary>Innerster Typ mit Abschnitten, in dessen Deklaration die Stelle liegt; -1 ohne.</summary>
    TypeNode: Integer;
    /// <summary>Alle Abschnitte des Typs in Quelltextreihenfolge.</summary>
    Sections: TAtlasVisibilitySections;
    /// <summary>Index des Abschnitts an der Stelle; -1 vor dem ersten Schlüsselwort.</summary>
    Current: Integer;
    /// <summary>Sichtbarkeit vor dem ersten Schlüsselwort: „published“ oder „public“.</summary>
    Implicit: string;
  end;

  TAtlasVisibilitySectionFinder = class
  public
    /// <summary>Abschnitt an der Stelle ALine/ACharacter (0-basiert). TypeNode -1 außerhalb eines Typs mit
    /// Abschnitten.</summary>
    class function At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer): TAtlasVisibilityPlace; static;
    /// <summary>Innerster Typ mit Abschnitten, in dessen eigenem Text die Stelle liegt: nicht auf seiner
    /// Kopfzeile (dort gilt der umgebende Typ), keine Vorwärtsdeklaration; -1 ohne.</summary>
    class function TypeAt(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer): Integer; static;
    /// <summary>Hat ein Typ dieser Art Sichtbarkeitsabschnitte (class, record, object, Helfer)?</summary>
    class function HasSections(const ANode: TAtlasOutlineNode): Boolean; static;
    /// <summary>Abschnitte des Typs AType in Quelltextreihenfolge, ohne die verschachtelter Typen.</summary>
    class function SectionsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      AType: Integer): TAtlasVisibilitySections; static;
    /// <summary>Sichtbarkeit vor dem ersten Schlüsselwort des Typs AType.</summary>
    class function ImplicitOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      AType: Integer): string; static;
    /// <summary>Mitglieder des Typs APlace.TypeNode im Abschnitt ASection (-1 = vor dem ersten) in
    /// Quelltextreihenfolge.</summary>
    class function MembersOf(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasVisibilityPlace;
      ASection: Integer): TArray<Integer>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.TypeText;

const
  cMaxAncestorDepth = 16;
  cPublished = 'published';
  cPublic = 'public';

  /// <summary>Klassen der RTL und VCL, die von TPersistent erben (ihre published-Mitglieder haben RTTI).</summary>
  cPersistentClasses: array[0..19] of string = ('tpersistent', 'tinterfacedpersistent', 'tcomponent',
    'tcontrol', 'twincontrol', 'tcustomcontrol', 'tgraphiccontrol', 'tcustomform', 'tform', 'tcustomframe',
    'tframe', 'tdatamodule', 'tcollection', 'tcollectionitem', 'townedcollection', 'tcustompanel', 'tpanel',
    'tcustomaction', 'taction', 'tbasicaction');

  /// <summary>Wörter vor einem Namen: Dort ist private usw. ein Bezeichner, kein Schlüsselwort.</summary>
  cDeclarationWords: array[0..5] of string = ('procedure', 'function', 'property', 'constructor', 'destructor',
    'operator');

/// <summary>Steht an AIndex ein Sichtbarkeitswort als Schlüsselwort und nicht als Bezeichner (Feld Public: …,
/// procedure Private, X.Public)?</summary>
function IsKeywordAt(const ATokens: TAtlasTypeTokens; AIndex: Integer): Boolean;
begin
  Result := ATokens[AIndex].Word and not ATokens[AIndex].Escaped and
    TAtlasTypeText.IsOneOf(ATokens[AIndex].Text, ['strict', 'private', 'protected', 'public', 'published']);
  if Result and (AIndex > 0) then
  begin
    Result := (ATokens[AIndex - 1].Text <> '.') and
      not TAtlasTypeText.IsOneOf(ATokens[AIndex - 1].Text, cDeclarationWords);
  end;
  if Result and (AIndex < High(ATokens)) then
  begin
    Result := (Length(ATokens[AIndex + 1].Text) <> 1) or
      not CharInSet(ATokens[AIndex + 1].Text[1], [':', '.', '(', '=', ',', '<', ')', ';']);
  end;
end;

/// <summary>strict mit folgendem private/protected; False, wenn strict allein steht.</summary>
function ReadStrict(const ATokens: TAtlasTypeTokens; var AIndex: Integer; out AKeyword: string): Boolean;
begin
  Result := (AIndex < High(ATokens)) and ATokens[AIndex + 1].Word and
    TAtlasTypeText.IsOneOf(ATokens[AIndex + 1].Text, ['private', 'protected']);
  if Result then
  begin
    AKeyword := 'strict ' + ATokens[AIndex + 1].Text;
    Inc(AIndex);
  end;
end;

/// <summary>Vorwärtsdeklaration: nach „=“ folgt nur class (und das Semikolon).</summary>
function IsForward(const ATokens: TAtlasTypeTokens): Boolean;
var
  mIndex, mRest: Integer;
begin
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    if ATokens[mIndex].Text = '=' then
    begin
      mRest := High(ATokens) - mIndex;
      Exit((ATokens[mIndex + 1].Text = 'class') and ((mRest = 1) or ((mRest = 2) and
        (ATokens[High(ATokens)].Text = ';'))));
    end;
  end;
  Result := False;
end;

function NewSection(const AKeyword: string; const AToken: TAtlasTypeToken): TAtlasVisibilitySection;
begin
  Result.Keyword := AKeyword;
  Result.Line := AToken.Line;
  Result.Character := AToken.Character;
end;

class function TAtlasVisibilitySectionFinder.HasSections(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := (ANode.Category = TAtlasOutlineCategory.TypeDecl) and
    TAtlasTypeText.IsOneOf(LowerCase(ANode.Detail), ['class', 'record', 'object', 'helper']);
end;

class function TAtlasVisibilitySectionFinder.SectionsOf(const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>; AType: Integer): TAtlasVisibilitySections;
var
  mTokens: TAtlasTypeTokens;
  mIndex: Integer;
  mKeyword: string;
  mStart: TAtlasTypeToken;
begin
  Result := nil;
  if (AType < 0) or (AType > High(ANodes)) then
  begin
    Exit;
  end;
  mTokens := TAtlasTypeText.Tokens(ANodes, ALines, AType);
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    if IsKeywordAt(mTokens, mIndex) then
    begin
      mStart := mTokens[mIndex];
      mKeyword := mStart.Text;
      if (mKeyword <> 'strict') or ReadStrict(mTokens, mIndex, mKeyword) then
      begin
        Result := Result + [NewSection(mKeyword, mStart)];
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Direktive {$M+}/{$TYPEINFO ON} in der Zeile: 1 an, -1 aus, 0 keine.</summary>
function TypeInfoSwitch(const ALine: string): Integer;
var
  mText: string;
begin
  Result := 0;
  mText := UpperCase(ALine).Replace(' ', '');
  if (Pos('{$M+}', mText) > 0) or (Pos('{$TYPEINFOON}', mText) > 0) then
  begin
    Result := 1;
  end
  else if (Pos('{$M-}', mText) > 0) or (Pos('{$TYPEINFOOFF}', mText) > 0) then
  begin
    Result := -1;
  end;
end;

/// <summary>Gilt {$M+} vor der Zeile ALine?</summary>
function TypeInfoOn(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mIndex, mSwitch: Integer;
begin
  Result := False;
  for mIndex := 0 to ALine do
  begin
    if mIndex > High(ALines) then
    begin
      Break;
    end;
    mSwitch := TypeInfoSwitch(ALines[mIndex]);
    if mSwitch <> 0 then
    begin
      Result := mSwitch > 0;
    end;
  end;
end;

/// <summary>Name des direkten Vorfahren aus „class(Vorfahr, …)“, klein und ohne Unit-Präfix; '' ohne.</summary>
function AncestorOf(const ATokens: TAtlasTypeTokens): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (mIndex < High(ATokens)) and (ATokens[mIndex].Text <> 'class') do
  begin
    Inc(mIndex);
  end;
  // Nach class: optional sealed/abstract, dann „(“.
  Inc(mIndex);
  while (mIndex <= High(ATokens)) and TAtlasTypeText.IsOneOf(ATokens[mIndex].Text, ['sealed', 'abstract']) do
  begin
    Inc(mIndex);
  end;
  if (mIndex > High(ATokens)) or (ATokens[mIndex].Text <> '(') then
  begin
    Exit;
  end;
  Inc(mIndex);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Word or (ATokens[mIndex].Text = '.')) do
  begin
    if ATokens[mIndex].Word then
    begin
      Result := ATokens[mIndex].Text;
    end;
    Inc(mIndex);
  end;
end;

function FindType(const ANodes: TAtlasOutlineNodes; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Category = TAtlasOutlineCategory.TypeDecl) and SameText(ANodes[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Erbt die Klasse AType von einer TPersistent-Klasse (bekannt oder über Vorfahren der Unit)?</summary>
function IsPersistent(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AType: Integer): Boolean;
var
  mDepth: Integer;
  mAncestor: string;
begin
  Result := False;
  for mDepth := 1 to cMaxAncestorDepth do
  begin
    if (AType < 0) or not SameText(ANodes[AType].Detail, 'class') then
    begin
      Exit;
    end;
    mAncestor := AncestorOf(TAtlasTypeText.Tokens(ANodes, ALines, AType));
    if mAncestor = '' then
    begin
      Exit;
    end;
    if TAtlasTypeText.IsOneOf(mAncestor, cPersistentClasses) then
    begin
      Exit(True);
    end;
    AType := FindType(ANodes, mAncestor);
  end;
end;

class function TAtlasVisibilitySectionFinder.ImplicitOf(const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>; AType: Integer): string;
begin
  Result := cPublic;
  if (AType < 0) or (AType > High(ANodes)) or not SameText(ANodes[AType].Detail, 'class') then
  begin
    Exit;
  end;
  if TypeInfoOn(ALines, ANodes[AType].StartLine) or IsPersistent(ANodes, ALines, AType) then
  begin
    Result := cPublished;
  end;
end;

function Contains(const ANode: TAtlasOutlineNode; ALine, ACharacter: Integer): Boolean;
begin
  Result := ((ALine > ANode.StartLine) or ((ALine = ANode.StartLine) and (ACharacter >= ANode.StartCharacter))) and
    ((ALine < ANode.EndLine) or ((ALine = ANode.EndLine) and (ACharacter <= ANode.EndCharacter)));
end;

class function TAtlasVisibilitySectionFinder.TypeAt(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  // Kinder stehen hinter ihren Eltern: von hinten ist der erste Treffer der innerste.
  for mIndex := High(ANodes) downto 0 do
  begin
    if not HasSections(ANodes[mIndex]) or not Contains(ANodes[mIndex], ALine, ACharacter) then
    begin
      Continue;
    end;
    // Auf der Kopfzeile eines Typs gilt der umgebende Typ; Vorwärtsdeklarationen haben keine Abschnitte.
    if (ALine <> ANodes[mIndex].NameLine) and not IsForward(TAtlasTypeText.Tokens(ANodes, ALines, mIndex)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasVisibilitySectionFinder.At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ALine, ACharacter: Integer): TAtlasVisibilityPlace;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasVisibilityPlace);
  Result.Current := -1;
  Result.TypeNode := TypeAt(ANodes, ALines, ALine, ACharacter);
  if Result.TypeNode < 0 then
  begin
    Exit;
  end;
  Result.Sections := SectionsOf(ANodes, ALines, Result.TypeNode);
  Result.Implicit := ImplicitOf(ANodes, ALines, Result.TypeNode);
  // Auch auf der Zeile des Schlüsselworts gilt schon sein Abschnitt.
  for mIndex := 0 to High(Result.Sections) do
  begin
    if Result.Sections[mIndex].Line <= ALine then
    begin
      Result.Current := mIndex;
    end;
  end;
end;

class function TAtlasVisibilitySectionFinder.MembersOf(const ANodes: TAtlasOutlineNodes;
  const APlace: TAtlasVisibilityPlace; ASection: Integer): TArray<Integer>;
var
  mIndex: Integer;
  mNode: TAtlasOutlineNode;
  mAfterStart, mBeforeEnd: Boolean;
begin
  Result := nil;
  if (APlace.TypeNode < 0) or (ASection > High(APlace.Sections)) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ANodes) do
  begin
    mNode := ANodes[mIndex];
    if (mNode.Parent <> APlace.TypeNode) or mNode.Hidden then
    begin
      Continue;
    end;
    mAfterStart := (ASection < 0) or not TAtlasTypeText.Before(mNode.NameLine, mNode.NameCharacter,
      APlace.Sections[ASection].Line, APlace.Sections[ASection].Character);
    mBeforeEnd := (ASection = High(APlace.Sections)) or TAtlasTypeText.Before(mNode.NameLine, mNode.NameCharacter,
      APlace.Sections[ASection + 1].Line, APlace.Sections[ASection + 1].Character);
    if mAfterStart and mBeforeEnd then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

end.
