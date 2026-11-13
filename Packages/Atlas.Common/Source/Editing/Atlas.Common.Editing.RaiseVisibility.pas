unit Atlas.Common.Editing.RaiseVisibility;

// „Sichtbarkeit anheben“ und „Eigenschaft anlegen“ für ein Mitglied einer
// Klasse (#2108):
//   - Sichtbarkeit anheben: verschiebt die Deklaration samt Doku-Kommentar
//     und Attributen in den Abschnitt protected bzw. public, legt ihn bei
//     Bedarf an und entfernt einen Abschnitt, der dadurch leer wird. Die
//     Implementierung bleibt unverändert. Angeboten für Felder,
//     Klassenvariablen, Methoden und Properties unterhalb der Zielsichtbarkeit,
//     nicht für published und nicht im ersten Abschnitt ohne Schlüsselwort
//     (dort stehen die Felder eines Formulars, die der Designer verwaltet).
//   - Eigenschaft anlegen: für ein nicht öffentliches Feld FName eine Property
//     Name im Abschnitt public, nur lesend oder lesend und schreibend direkt
//     auf das Feld. Nur, wenn der Name frei ist.
// Beide Aktionen ändern nur die Klassendeklaration; der Client übernimmt sie
// als einen Rückgängig-Schritt. Die Vervollständigung bietet sie für Mitglieder
// an, die an der Cursorstelle nicht sichtbar sind; Sichtbarkeit anheben steht
// auch als Code-Aktion auf der Deklaration.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.CodeActions;

const
  /// <summary>Kennungen der Aktionen in data.tag, damit die Vervollständigung sie findet.</summary>
  cRaiseVisibilityTag = 'member.raiseVisibility';
  cCreatePropertyTag = 'member.createProperty';

type
  TRaiseVisibility = class
  public
    /// <summary>Abschnitte, in die AIndex gehoben werden kann (protected, public), aufsteigend; leer bei published,
    /// public, im ersten Abschnitt ohne Schlüsselwort und bei anderen Mitgliedern als Feld, Klassenvariable,
    /// Methode oder Property.</summary>
    class function Targets(ALayout: TClassLayout; AIndex: Integer): TArray<TClassVisibility>; static;
    /// <summary>Änderungen, die AIndex in den Abschnitt ATarget setzen; False, wenn das nicht geht.</summary>
    class function RaiseEdits(ALayout: TClassLayout; AIndex: Integer; ATarget: TClassVisibility;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Name der Property für das Feld AIndex (FName → Name); '' bei anderen Mitgliedern, bei public und
    /// published, ohne F-Präfix vor einem Großbuchstaben und wenn die Klasse den Namen schon hat.</summary>
    class function PropertyName(ALayout: TClassLayout; AIndex: Integer): string; static;
    /// <summary>Property für das Feld AIndex im Abschnitt public; AWritable mit write. False ohne PropertyName.
    /// </summary>
    class function PropertyEdits(ALayout: TClassLayout; AIndex: Integer; AWritable: Boolean;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Mitglied in der Deklaration an APosition: das mit dem Namen AName, sonst das Wort an APosition
    /// (Feldgruppe), sonst das der Zeile; -1 ohne.</summary>
    class function MemberAt(ALayout: TClassLayout; const APosition: TTextPosition; const AName: string): Integer;
      static;
    /// <summary>Code-Aktionen „Sichtbarkeit von X auf … anheben“ für das Mitglied an APosition (siehe MemberAt);
    /// mit AProperties auch „Eigenschaft … anlegen“. Leer außerhalb einer Klassendeklaration.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const AName: string; AProperties: Boolean): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRaiseVisibilityText = (RaiseTo, PropertyReadOnly, PropertyReadWrite);

const
  cTexts: array[TRaiseVisibilityText] of TAtlasText = (
    (De: 'Sichtbarkeit von %s auf %s anheben'; En: 'Raise visibility of %s to %s'),
    (De: 'Eigenschaft %s in %s anlegen (nur lesen)'; En: 'Create property %s in %s (read-only)'),
    (De: 'Eigenschaft %s in %s anlegen (lesen und schreiben)'; En: 'Create property %s in %s (read and write)'));

{$SCOPEDENUMS OFF}

const
  cRaisableKinds = [TClassMemberKind.Field, TClassMemberKind.ClassVar, TClassMemberKind.Method,
    TClassMemberKind.Constructor_, TClassMemberKind.Destructor_, TClassMemberKind.Property_];
  cTargets: array[0..1] of TClassVisibility = (TClassVisibility.Protected_, TClassVisibility.Public_);

/// <summary>Steht AIndex im ersten Abschnitt ohne Schlüsselwort?</summary>
function InDefaultSection(ALayout: TClassLayout; AIndex: Integer): Boolean;
var
  mSection: TClassSection;
begin
  for mSection in ALayout.Sections do
  begin
    if TMemberTransfer.Has(mSection.Members, AIndex) then
    begin
      Exit(mSection.HeadLine < 0);
    end;
  end;
  Result := False;
end;

class function TRaiseVisibility.Targets(ALayout: TClassLayout; AIndex: Integer): TArray<TClassVisibility>;
var
  mTarget: TClassVisibility;
begin
  Result := nil;
  if not (ALayout.Members[AIndex].Kind in cRaisableKinds) or InDefaultSection(ALayout, AIndex) then
  begin
    Exit;
  end;
  for mTarget in cTargets do
  begin
    if ALayout.Members[AIndex].Visibility < mTarget then
    begin
      Result := Result + [mTarget];
    end;
  end;
end;

class function TRaiseVisibility.RaiseEdits(ALayout: TClassLayout; AIndex: Integer; ATarget: TClassVisibility;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mText: string;
  mTarget: TClassVisibility;
begin
  AEdits := nil;
  Result := False;
  for mTarget in Targets(ALayout, AIndex) do
  begin
    Result := Result or (mTarget = ATarget);
  end;
  if not Result then
  begin
    Exit;
  end;
  mText := ALayout.Text;
  Result := TMemberTransfer.Relocate(mText, ALayout.Name, [ALayout.Members[AIndex]], ATarget);
  if Result then
  begin
    AEdits := TTextChanges.Diff(ALayout.Text, mText);
    Result := AEdits <> nil;
  end;
end;

/// <summary>Feld mit Typ unterhalb von public?</summary>
function IsHiddenField(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Kind = TClassMemberKind.Field) and (AMember.Visibility < TClassVisibility.Public_) and
    (AMember.TypeName <> '');
end;

/// <summary>AName ohne das F vor einem Großbuchstaben (FName → Name); '' ohne dieses Präfix.</summary>
function WithoutFieldPrefix(const AName: string): string;
begin
  Result := '';
  if (Length(AName) >= 2) and CharInSet(AName[1], ['F', 'f']) and CharInSet(AName[2], ['A'..'Z']) then
  begin
    Result := Copy(AName, 2, MaxInt);
  end;
end;

class function TRaiseVisibility.PropertyName(ALayout: TClassLayout; AIndex: Integer): string;
begin
  Result := '';
  if IsHiddenField(ALayout.Members[AIndex]) then
  begin
    Result := WithoutFieldPrefix(ALayout.Members[AIndex].Name);
  end;
  if (Result <> '') and (ALayout.Find(Result) <> nil) then
  begin
    Result := '';
  end;
end;

class function TRaiseVisibility.PropertyEdits(ALayout: TClassLayout; AIndex: Integer; AWritable: Boolean;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mName, mDeclaration: string;
begin
  AEdits := nil;
  mName := PropertyName(ALayout, AIndex);
  Result := mName <> '';
  if not Result then
  begin
    Exit;
  end;
  mDeclaration := Format('property %s: %s read %s', [mName, ALayout.Members[AIndex].TypeName,
    ALayout.Members[AIndex].Name]);
  if AWritable then
  begin
    mDeclaration := mDeclaration + ' write ' + ALayout.Members[AIndex].Name;
  end;
  AEdits := [TClassEdits.InsertMembers(ALayout, TClassVisibility.Public_, False, [mDeclaration + ';'])];
end;

/// <summary>Bezeichner an APosition; '' ohne.</summary>
function WordAt(ALayout: TClassLayout; const APosition: TTextPosition): string;
var
  mToken: TPascalToken;
begin
  for mToken in ALayout.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.StartPos.Line = APosition.Line) and
      (mToken.StartPos.Character <= APosition.Character) and (mToken.EndPos.Character >= APosition.Character) then
    begin
      Exit(mToken.Text);
    end;
  end;
  Result := '';
end;

/// <summary>Mitglied AName, dessen Deklaration ALine enthält; ohne solches das erste mit dem Namen; -1 ohne.
/// </summary>
function NamedMember(ALayout: TClassLayout; ALine: Integer; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex in ALayout.Find(AName) do
  begin
    if (ALine >= ALayout.Members[mIndex].FirstLine) and (ALine <= ALayout.Members[mIndex].LastLine) then
    begin
      Exit(mIndex);
    end;
    if Result < 0 then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TRaiseVisibility.MemberAt(ALayout: TClassLayout; const APosition: TTextPosition;
  const AName: string): Integer;
var
  mWord: string;
begin
  if AName <> '' then
  begin
    Exit(NamedMember(ALayout, APosition.Line, AName));
  end;
  Result := ALayout.MemberAtLine(APosition.Line);
  mWord := WordAt(ALayout, APosition);
  if (Result >= 0) and (mWord <> '') and ALayout.Members[Result].IsFieldGroup then
  begin
    Result := NamedMember(ALayout, APosition.Line, mWord);
  end;
end;

/// <summary>Code-Aktion mit Titel, Tag und Änderungen.</summary>
function NewAction(const ATitle, ATag: string; const AEdits: TArray<TTextEdit>): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := ATitle;
  Result.Kind := cRewriteKind;
  Result.Tag := ATag;
  Result.Edits := AEdits;
end;

/// <summary>„Sichtbarkeit anheben“ für jedes Ziel von AIndex.</summary>
function RaiseActions(ALayout: TClassLayout; AIndex: Integer): TArray<TCodeAction>;
var
  mTarget: TClassVisibility;
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  for mTarget in TRaiseVisibility.Targets(ALayout, AIndex) do
  begin
    if TRaiseVisibility.RaiseEdits(ALayout, AIndex, mTarget, mEdits) then
    begin
      Result := Result + [NewAction(Format(cTexts[TRaiseVisibilityText.RaiseTo].Text,
        [ALayout.Members[AIndex].Name, TClassEdits.VisibilityName(mTarget)]), cRaiseVisibilityTag, mEdits)];
    end;
  end;
end;

/// <summary>„Eigenschaft anlegen“ nur lesend und lesend und schreibend für das Feld AIndex.</summary>
function PropertyActions(ALayout: TClassLayout; AIndex: Integer): TArray<TCodeAction>;
var
  mName: string;
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  mName := TRaiseVisibility.PropertyName(ALayout, AIndex);
  if TRaiseVisibility.PropertyEdits(ALayout, AIndex, False, mEdits) then
  begin
    Result := Result + [NewAction(Format(cTexts[TRaiseVisibilityText.PropertyReadOnly].Text,
      [mName, ALayout.Name]), cCreatePropertyTag, mEdits)];
  end;
  if TRaiseVisibility.PropertyEdits(ALayout, AIndex, True, mEdits) then
  begin
    Result := Result + [NewAction(Format(cTexts[TRaiseVisibilityText.PropertyReadWrite].Text,
      [mName, ALayout.Name]), cCreatePropertyTag, mEdits)];
  end;
end;

class function TRaiseVisibility.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const AName: string; AProperties: Boolean): TArray<TCodeAction>;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mIndex: Integer;
begin
  Result := nil;
  mDecl := TClassLayout.DeclAt(ATree, APosition.Line, True);
  if mDecl = nil then
  begin
    Exit;
  end;
  mLayout := TClassLayout.Read(ATree, AText, mDecl);
  try
    mIndex := MemberAt(mLayout, APosition, AName);
    if mIndex < 0 then
    begin
      Exit;
    end;
    if AProperties then
    begin
      Result := PropertyActions(mLayout, mIndex);
    end;
    Result := Result + RaiseActions(mLayout, mIndex);
  finally
    mLayout.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.RaiseVisibility', cTexts);

end.
