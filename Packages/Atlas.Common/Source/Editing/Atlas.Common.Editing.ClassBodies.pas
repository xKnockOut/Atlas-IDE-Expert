unit Atlas.Common.Editing.ClassBodies;

// Rümpfe der Klassenvervollständigung (#1834), gemeinsam für TClassCompletion
// und TMethodOrder:
// - TTypeShape liest aus dem Typ, was die Rümpfe brauchen: Vorfahr, Felder,
//   Properties mit read/write und die Kurzbeschreibung der Summary (K3).
// - RankOf ordnet eine Methode in eine Gruppe (R2, #1836): Lebenszyklus
//   (class constructor, class destructor, constructor, destructor,
//   AfterConstruction, BeforeDestruction), Zugriffsmethoden der Properties als
//   Paar in Reihenfolge der Properties, überschriebene, übrige.
// - StubLines füllt einen neuen Rumpf vor (O1, #1837): inherited bei override,
//   Konstruktor und Destruktor, Result := FName bzw. FName := AValue bei
//   Getter und Setter mit eindeutigem Feld.
// - Wrapped setzt den Kommentar über den Abschnitt eines Typs (K1–K4, #1835).
// Die Einstellungen kommen über TClassBodyOptions (classCompletion.*).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.TypeComments;

type
  /// <summary>Einstellungen der Klassenvervollständigung, wie die Erzeuger sie brauchen.</summary>
  TClassBodyOptions = record
    TypeComment: TTypeCommentStyle;
    BodyStubs: Boolean;
    LifecycleFirst: Boolean;
    /// <summary>Breite der Trennlinie (K2); 0 = Vorgabe.</summary>
    LineLength: Integer;
    /// <summary>Eine Ebene Einrückung im Rumpf.</summary>
    Indent: string;
    /// <summary>brace, vorbefüllt, Lebenszyklus zuerst, zwei Leerzeichen.</summary>
    class function Default: TClassBodyOptions; static;
    class function FromSettings(const ASettings: TClassCompletionSettings;
      const AStyle: TFormatStyle): TClassBodyOptions; static;
    /// <summary>Aus den Einstellungen der Schnellbefehle (TSlashSettings); AHost nil: Default mit AStyle.</summary>
    class function FromHost(const AHost: ISlashHost; const AUri: string;
      const AStyle: TFormatStyle): TClassBodyOptions; static;
  end;

  TTypeProperty = record
    Name: string;
    TypeName: string;
    ReadName: string;
    WriteName: string;
    /// <summary>Array-Property oder mit index-Angabe.</summary>
    Indexed: Boolean;
  end;

  /// <summary>Was die Rümpfe eines Typs aus seiner Deklaration brauchen.</summary>
  TTypeShape = record
    TypeName: string;
    IsClass: Boolean;
    /// <summary>Erster Eintrag der Vorfahrenliste; '' ohne.</summary>
    Ancestor: string;
    Fields: TArray<TIndexSymbol>;
    Properties: TArray<TTypeProperty>;
    /// <summary>Erste Zeile der Summary über dem Typ (K3); '' ohne.</summary>
    Summary: string;
    /// <summary>Typ ATypeName ("TAussen.TInnen") aus AUnit; leer, wenn es ihn nicht gibt.</summary>
    class function Read(const AUnit: TUnitIndex; const ALines: TArray<string>;
      const ATypeName: string): TTypeShape; static;
    /// <summary>Typ des Felds AName; False ohne.</summary>
    function FieldType(const AName: string; out ATypeName: string): Boolean;
  end;

  /// <summary>Rang einer Methode beim Ordnen (R2): Gruppe, darin Stelle.</summary>
  TMethodRank = record
    Group: Integer;
    Sub: Integer;
  end;

  TClassBodies = class
  public const
    GroupLifecycle = 0;
    GroupAccessor = 1;
    GroupOverride = 2;
    GroupOther = 3;
  public
    /// <summary>Deklaration ARange als eine Zeile (Zeilen mit Leerzeichen verbunden).</summary>
    class function DeclarationText(const ALines: TArray<string>; const ARange: TTextRange): string; static;
    /// <summary>Rang der Methode AName mit Deklaration ADeclaration ("constructor Create; override").</summary>
    class function RankOf(const AShape: TTypeShape; const ADeclaration, AName: string): TMethodRank; static;
    /// <summary>Zeilen zwischen begin und end für einen neuen Rumpf; nil = leer lassen.</summary>
    class function StubLines(const AShape: TTypeShape; const ADeclaration, AName, AIndent: string): TArray<string>;
      static;
    /// <summary>Ganzer Rumpf: AHeader (mit ";"), begin, Vorbefüllung bzw. Leerzeile, end;.</summary>
    class function Body(const AShape: TTypeShape; const AHeader, ADeclaration, AName: string;
      const AOptions: TClassBodyOptions; const ALineBreak: string): string; static;
    /// <summary>ABodies mit dem Kommentar des Typs davor (bei Region auch {$ENDREGION} dahinter).</summary>
    class function Wrapped(const AShape: TTypeShape; const AOptions: TClassBodyOptions;
      const ABodies, ALineBreak: string): string; static;
    /// <summary>Steht im implementation-Teil von ALines (ab AFromLine) schon ein Kommentar zu ATypeName?</summary>
    class function HasTypeComment(const ALines: TArray<string>; AFromLine: Integer;
      const ATypeName: string): Boolean; static;
    /// <summary>Namen der Parameter im Kopf AHeader in Reihenfolge.</summary>
    class function ParameterNames(const AHeader: string): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Text.Lines,
  Atlas.Common.Editing.RoutineBody;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];

function HasWord(const AText, AWord: string): Boolean;
var
  mIndex, mAfter: Integer;
  mLower: string;
begin
  mLower := LowerCase(AText);
  mIndex := Pos(AWord, mLower);
  while mIndex > 0 do
  begin
    mAfter := mIndex + Length(AWord);
    if ((mIndex = 1) or not CharInSet(mLower[mIndex - 1], ['a'..'z', '0'..'9', '_'])) and
      ((mAfter > Length(mLower)) or not CharInSet(mLower[mAfter], ['a'..'z', '0'..'9', '_'])) then
    begin
      Exit(True);
    end;
    mIndex := PosEx(AWord, mLower, mIndex + 1);
  end;
  Result := False;
end;

function TypeNameOf(const ASymbol: TIndexSymbol): string;
begin
  Result := ASymbol.Name;
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + '.' + ASymbol.Name;
  end;
end;

/// <summary>Wort hinter AKeyword in AText bis zum nächsten Leerraum oder ";"; '' ohne.</summary>
function WordAfter(const AText, AKeyword: string): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mParts := StringReplace(AText, ';', ' ', [rfReplaceAll]).Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mParts) - 1 do
  begin
    if SameText(mParts[mIndex], AKeyword) then
    begin
      Exit(mParts[mIndex + 1]);
    end;
  end;
end;

{ TClassBodyOptions }

class function TClassBodyOptions.Default: TClassBodyOptions;
begin
  Result.TypeComment := TTypeCommentStyle.Brace;
  Result.BodyStubs := True;
  Result.LifecycleFirst := True;
  Result.LineLength := 0;
  Result.Indent := '  ';
end;

class function TClassBodyOptions.FromSettings(const ASettings: TClassCompletionSettings;
  const AStyle: TFormatStyle): TClassBodyOptions;
var
  mSettings: TClassCompletionSettings;
begin
  // Ungesetzt (leerer Datensatz, z. B. im Prüflauf ohne Einstellungen): Vorgaben.
  mSettings := ASettings;
  if mSettings.TypeComment = '' then
  begin
    mSettings := TClassCompletionSettings.Default;
  end;
  Result.TypeComment := TTypeComments.StyleOf(mSettings.TypeComment);
  Result.BodyStubs := mSettings.BodyStubs;
  Result.LifecycleFirst := mSettings.LifecycleFirst;
  Result.LineLength := AStyle.MaxLineLength;
  Result.Indent := TRoutineBody.IndentUnit(AStyle);
end;

class function TClassBodyOptions.FromHost(const AHost: ISlashHost; const AUri: string;
  const AStyle: TFormatStyle): TClassBodyOptions;
var
  mSettings: TClassCompletionSettings;
begin
  mSettings := TClassCompletionSettings.Default;
  if AHost <> nil then
  begin
    mSettings.TypeComment := AHost.Setting(AUri, TSlashSettings.TypeComment);
    mSettings.BodyStubs := not SameText(AHost.Setting(AUri, TSlashSettings.BodyStubs), 'false');
    mSettings.LifecycleFirst := not SameText(AHost.Setting(AUri, TSlashSettings.LifecycleFirst), 'false');
  end;
  Result := FromSettings(mSettings, AStyle);
end;

{ TTypeShape }

function PropertyOf(const ALines: TArray<string>; const ASymbol: TIndexSymbol): TTypeProperty;
var
  mText, mHead: string;
begin
  mText := TClassBodies.DeclarationText(ALines, ASymbol.Range);
  Result := Default(TTypeProperty);
  Result.Name := ASymbol.Name;
  Result.TypeName := ASymbol.TypeName;
  Result.ReadName := WordAfter(mText, 'read');
  Result.WriteName := WordAfter(mText, 'write');
  mHead := Copy(mText, 1, Pos(':', mText));
  Result.Indexed := (Pos('[', mHead) > 0) or HasWord(mText, 'index') or (ASymbol.MaxArgs > 0);
end;

class function TTypeShape.Read(const AUnit: TUnitIndex; const ALines: TArray<string>;
  const ATypeName: string): TTypeShape;
var
  mSymbol, mType: TIndexSymbol;
  mFound: Boolean;
begin
  Result := Default(TTypeShape);
  Result.TypeName := ATypeName;
  mFound := False;
  mType := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if not mFound and (mSymbol.Kind in TypeKinds) and SameText(TypeNameOf(mSymbol), ATypeName) then
    begin
      mType := mSymbol;
      mFound := True;
    end
    else if SameText(mSymbol.Container, ATypeName) and (mSymbol.Kind = TIndexSymbolKind.Field) then
    begin
      Result.Fields := Result.Fields + [mSymbol];
    end
    else if SameText(mSymbol.Container, ATypeName) and (mSymbol.Kind = TIndexSymbolKind.Property_) then
    begin
      Result.Properties := Result.Properties + [PropertyOf(ALines, mSymbol)];
    end;
  end;
  Result.IsClass := mFound and (mType.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType]);
  if mFound and (Length(mType.Ancestors) > 0) then
  begin
    Result.Ancestor := mType.Ancestors[0];
  end;
  if mFound then
  begin
    Result.Summary := TTypeComments.SummaryAbove(ALines, mType.Range.StartPos.Line);
  end;
end;

function TTypeShape.FieldType(const AName: string; out ATypeName: string): Boolean;
var
  mField: TIndexSymbol;
begin
  for mField in Fields do
  begin
    if SameText(mField.Name, AName) then
    begin
      ATypeName := mField.TypeName;
      Exit(True);
    end;
  end;
  ATypeName := '';
  Result := False;
end;

{ TClassBodies }

class function TClassBodies.DeclarationText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Trim(Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt));
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
end;

/// <summary>Stelle im Lebenszyklus; -1, wenn die Methode nicht dazugehört.</summary>
function LifecycleSub(const ALower, AName: string): Integer;
begin
  Result := -1;
  if StartsStr('class constructor', ALower) then
  begin
    Result := 0;
  end
  else if StartsStr('class destructor', ALower) then
  begin
    Result := 1;
  end
  else if StartsStr('constructor', ALower) then
  begin
    Result := 2;
  end
  else if StartsStr('destructor', ALower) then
  begin
    Result := 3;
  end
  else if SameText(AName, 'AfterConstruction') then
  begin
    Result := 4;
  end
  else if SameText(AName, 'BeforeDestruction') then
  begin
    Result := 5;
  end;
end;

/// <summary>Stelle unter den Zugriffsmethoden: Property je zwei Plätze (read, write); -1 ohne.</summary>
function AccessorSub(const AShape: TTypeShape; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AShape.Properties) do
  begin
    if SameText(AShape.Properties[mIndex].ReadName, AName) then
    begin
      Exit(2 * mIndex);
    end;
    if SameText(AShape.Properties[mIndex].WriteName, AName) then
    begin
      Exit(2 * mIndex + 1);
    end;
  end;
  Result := -1;
end;

class function TClassBodies.RankOf(const AShape: TTypeShape; const ADeclaration, AName: string): TMethodRank;
var
  mLower: string;
begin
  mLower := LowerCase(Trim(ADeclaration));
  Result.Sub := LifecycleSub(mLower, AName);
  if Result.Sub >= 0 then
  begin
    Result.Group := GroupLifecycle;
    Exit;
  end;
  Result.Sub := AccessorSub(AShape, AName);
  if Result.Sub >= 0 then
  begin
    Result.Group := GroupAccessor;
    Exit;
  end;
  Result.Sub := 0;
  Result.Group := GroupOther;
  if HasWord(mLower, 'override') then
  begin
    Result.Group := GroupOverride;
  end;
end;

/// <summary>Parametergruppen in der ersten Klammer von AHeader ("const A, B: Integer"), getrennt an ";" außerhalb
/// von Klammern und Zeichenketten.</summary>
function ParameterGroups(const AHeader: string): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mQuoted: Boolean;
begin
  Result := nil;
  mStart := Pos('(', AHeader);
  if mStart = 0 then
  begin
    Exit;
  end;
  mDepth := 0;
  mQuoted := False;
  for mIndex := mStart to Length(AHeader) do
  begin
    if AHeader[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and CharInSet(AHeader[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if not mQuoted and CharInSet(AHeader[mIndex], [')', ']', '>']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Result + [Copy(AHeader, mStart + 1, mIndex - mStart - 1)]);
      end;
    end
    else if not mQuoted and (mDepth = 1) and (AHeader[mIndex] = ';') then
    begin
      Result := Result + [Copy(AHeader, mStart + 1, mIndex - mStart - 1)];
      mStart := mIndex;
    end;
  end;
  Result := nil;
end;

class function TClassBodies.ParameterNames(const AHeader: string): TArray<string>;
var
  mGroup, mNames, mName: string;
begin
  Result := nil;
  for mGroup in ParameterGroups(AHeader) do
  begin
    mNames := Trim(mGroup);
    if Pos(':', mNames) > 0 then
    begin
      mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
    end;
    for mName in mNames.Split([',']) do
    begin
      // Letztes Wort: const, var, out und constref stehen davor.
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(Copy(Trim(mName), LastDelimiter(' ', Trim(mName)) + 1, MaxInt))];
      end;
    end;
  end;
end;

/// <summary>"inherited Name(A, B)" mit den Parametern des Kopfs.</summary>
function InheritedCall(const ADeclaration, AName: string): string;
var
  mNames: TArray<string>;
begin
  Result := 'inherited ' + AName;
  mNames := TClassBodies.ParameterNames(ADeclaration);
  if Length(mNames) > 0 then
  begin
    Result := Result + '(' + string.Join(', ', mNames) + ')';
  end;
end;

/// <summary>Vorbefüllung für Konstruktor und Destruktor; nil ohne.</summary>
function LifecycleStub(const AShape: TTypeShape; const ALower, ADeclaration: string): TArray<string>;
var
  mNames: TArray<string>;
begin
  Result := nil;
  if not AShape.IsClass or StartsStr('class ', ALower) then
  begin
    Exit;
  end;
  if StartsStr('destructor', ALower) then
  begin
    if HasWord(ALower, 'override') then
    begin
      Result := TArray<string>.Create('', 'inherited;');
    end;
  end
  else if HasWord(ALower, 'override') then
  begin
    Result := TArray<string>.Create('inherited;');
  end
  else if (AShape.Ancestor <> '') and not SameText(AShape.Ancestor, 'TObject') then
  begin
    mNames := TClassBodies.ParameterNames(ADeclaration);
    if (Length(mNames) > 0) and SameText(mNames[0], 'AOwner') then
    begin
      Result := TArray<string>.Create('inherited Create(AOwner);');
    end
    else
    begin
      Result := TArray<string>.Create('inherited Create;');
    end;
  end;
end;

/// <summary>Result := FName bzw. FName := AValue für Getter und Setter einer Property mit Feld F&lt;Name&gt;.</summary>
function AccessorStub(const AShape: TTypeShape; const ALower, ADeclaration, AName: string): TArray<string>;
var
  mProperty: TTypeProperty;
  mFieldType: string;
  mNames: TArray<string>;
begin
  Result := nil;
  mNames := TClassBodies.ParameterNames(ADeclaration);
  for mProperty in AShape.Properties do
  begin
    if mProperty.Indexed or not AShape.FieldType('F' + mProperty.Name, mFieldType) or
      not SameText(mFieldType, mProperty.TypeName) then
    begin
      Continue;
    end;
    if SameText(mProperty.ReadName, AName) and StartsStr('function', ALower) and (Length(mNames) = 0) then
    begin
      Exit(TArray<string>.Create('Result := F' + mProperty.Name + ';'));
    end;
    if SameText(mProperty.WriteName, AName) and StartsStr('procedure', ALower) and (Length(mNames) = 1) then
    begin
      Exit(TArray<string>.Create('F' + mProperty.Name + ' := ' + mNames[0] + ';'));
    end;
  end;
end;

class function TClassBodies.StubLines(const AShape: TTypeShape; const ADeclaration, AName, AIndent: string):
  TArray<string>;
var
  mLower: string;
  mIndex: Integer;
begin
  mLower := LowerCase(Trim(ADeclaration));
  if StartsStr('constructor', mLower) or StartsStr('destructor', mLower) or StartsStr('class ', mLower) then
  begin
    Result := LifecycleStub(AShape, mLower, ADeclaration);
  end
  else if HasWord(mLower, 'override') and not HasWord(mLower, 'abstract') and AShape.IsClass then
  begin
    Result := TArray<string>.Create(InheritedCall(ADeclaration, AName) + ';');
    if StartsStr('function', mLower) then
    begin
      Result[0] := 'Result := ' + Result[0];
    end;
  end
  else
  begin
    Result := AccessorStub(AShape, mLower, ADeclaration, AName);
  end;
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex] <> '' then
    begin
      Result[mIndex] := AIndent + Result[mIndex];
    end;
  end;
end;

class function TClassBodies.Body(const AShape: TTypeShape; const AHeader, ADeclaration, AName: string;
  const AOptions: TClassBodyOptions; const ALineBreak: string): string;
var
  mStub: TArray<string>;
begin
  mStub := nil;
  if AOptions.BodyStubs then
  begin
    mStub := StubLines(AShape, ADeclaration, AName, AOptions.Indent);
  end;
  if mStub = nil then
  begin
    mStub := TArray<string>.Create('');
  end;
  Result := AHeader + ALineBreak + 'begin' + ALineBreak + TTextLines.JoinLines(mStub, ALineBreak) + ALineBreak +
    'end;';
end;

class function TClassBodies.Wrapped(const AShape: TTypeShape; const AOptions: TClassBodyOptions;
  const ABodies, ALineBreak: string): string;
var
  mHeader: TArray<string>;
begin
  mHeader := TTypeComments.Header(AOptions.TypeComment, AShape.TypeName, AShape.Summary, AOptions.LineLength);
  if mHeader = nil then
  begin
    Exit(ABodies);
  end;
  if AOptions.TypeComment = TTypeCommentStyle.Region then
  begin
    Result := mHeader[0] + ALineBreak + ABodies + ALineBreak + TTypeComments.RegionEndText;
  end
  else
  begin
    Result := TTextLines.JoinLines(mHeader, ALineBreak) + ALineBreak + ALineBreak + ABodies;
  end;
end;

class function TClassBodies.HasTypeComment(const ALines: TArray<string>; AFromLine: Integer;
  const ATypeName: string): Boolean;
var
  mLine: Integer;
  mCopy: string;
begin
  for mLine := Max(AFromLine, 0) to High(ALines) do
  begin
    if TTypeComments.Renamed(ALines[mLine], ATypeName, ATypeName, mCopy) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
