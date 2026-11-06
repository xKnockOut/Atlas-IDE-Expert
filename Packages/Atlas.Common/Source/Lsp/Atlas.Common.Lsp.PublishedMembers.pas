unit Atlas.Common.Lsp.PublishedMembers;

// published-Properties und Ereignisse einer Komponentenklasse für den Hover,
// inklusive geerbter, mit Typ, default-Wert und deklarierender Klasse (#110).
//
// Die Klassen werden über den Symbolindex gefunden und ihre Deklaration aus
// dem Quelltext gelesen, weil der Index keine Sichtbarkeiten speichert.
// Mitglieder vor dem ersten Sichtbarkeitsabschnitt gelten als published
// (Komponenten werden mit {$M+} übersetzt). Eine Neudeklaration ohne Typ
// (property Caption;) macht eine geerbte Property published; Typ, default
// und deklarierende Klasse kommen dann vom Vorfahren.
//
// Ereignisse erkennt Atlas am Typ, nicht am Namen: ein Methodenzeiger
// (procedure/function … of object) oder eine Methodenreferenz
// (reference to …), auch über Aliase. Steht der Typ nicht im Index, gilt nur
// TNotifyEvent als Ereignis.
//
// Vorgabewerte: ausdrückliches default, implizites (Boolean False,
// Ganzzahlen 0, Aufzählungen ihr erster Wert), nodefault und stored
// erscheinen unterschiedlich; default an einer Array-Property heißt
// Standard-Property und steht als eigene Zeile.
//
// Für den Atlas-Tooltip liefert ToJson dieselben Mitglieder strukturiert
// (atlas.published): je Mitglied Name, Typ, Vorgabe samt Art, stored,
// deklarierende Klasse und Ereignis-Kennung, dazu die Standard-Property.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract;

type
  TMemberReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  {$SCOPEDENUMS ON}
  TPublishedDefaultKind = (
    /// <summary>Keine Angabe, kein impliziter Wert bekannt.</summary>
    None,
    /// <summary>default Wert in der Deklaration.</summary>
    Explicit,
    /// <summary>Kein default, aber der Anfangswert des Typs (False, 0, erster Aufzählungswert).</summary>
    Implicit,
    /// <summary>nodefault: immer gespeichert.</summary>
    NoDefault);
  {$SCOPEDENUMS OFF}

  TPublishedMember = record
    Name: string;
    TypeName: string;
    /// <summary>Wert nach default bzw. der implizite Wert; '' ohne.</summary>
    DefaultValue: string;
    DefaultKind: TPublishedDefaultKind;
    /// <summary>Text nach stored (False, IsCaptionStored …); '' ohne Angabe.</summary>
    Stored: string;
    /// <summary>Klasse, die die Property mit Typ deklariert.</summary>
    DeclaringClass: string;
    /// <summary>Klasse, in der die Property published wird (Neudeklaration).</summary>
    PublishedIn: string;
    IsEvent: Boolean;
  end;

  TPublishedMembers = class
  public const
    /// <summary>Ab so vielen Einträgen werden nur noch Namen je Klasse gezeigt.</summary>
    cCompactLimit = 40;
    cMaxDepth = 32;
    /// <summary>Signatur, wenn der Ereignistyp nicht im Index steht.</summary>
    cNotifyTail = '(Sender: TObject)';
    /// <summary>Alle published-Mitglieder, abgeleitete Klassen zuerst.</summary>
    class function Collect(const AIndex: ISymbolIndex; const AClassName: string;
      const AReadText: TMemberReadText): TArray<TPublishedMember>; static;
    /// <summary>Standard-Property der Klasse oder eines Vorfahren (Array-Property mit default), z. B.
    /// "Strings[Index: Integer]: string"; '' ohne.</summary>
    class function DefaultProperty(const AIndex: ISymbolIndex; const AClassName: string;
      const AReadText: TMemberReadText): string; static;
    /// <summary>Ist ATypeName ein Methodenzeiger oder eine Methodenreferenz (auch über Aliase)?</summary>
    class function IsEventType(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
      const ATypeName: string): Boolean; static;
    /// <summary>Parameter und ggf. Rückgabetyp des Ereignisses AEventName von AComponentClass,
    /// z. B. "(Sender: TObject)", aus der Deklaration des Ereignistyps im Index.</summary>
    class function EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
      const AComponentClass, AEventName: string; out ATail: string): Boolean; static;
    /// <summary>"default 5", "default False (implizit)", "nodefault", dazu "stored …"; '' ohne Angabe.</summary>
    class function DefaultText(const AMember: TPublishedMember): string; static;
    /// <summary>Markdown-Abschnitt für den Hover; '' ohne Mitglieder.</summary>
    class function ToMarkdown(const AMembers: TArray<TPublishedMember>): string; overload; static;
    /// <summary>Wie oben, davor die Standard-Property (aus DefaultProperty), wenn nicht ''.</summary>
    class function ToMarkdown(const AMembers: TArray<TPublishedMember>;
      const ADefaultProperty: string): string; overload; static;
    /// <summary>atlas.published für den Tooltip (#110): {"members": [{"name", "type", "default", "defaultKind"
    /// (explicit, implicit, nodefault), "stored", "declaringClass", "publishedIn", "event"}], "defaultProperty"};
    /// leere Angaben fehlen. nil ohne Mitglieder und Standard-Property; sonst gehört das Objekt dem Aufrufer.
    /// </summary>
    class function ToJson(const AMembers: TArray<TPublishedMember>; const ADefaultProperty: string): TJSONObject;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPublishedMembersText = (DefaultImplicit, Implicit, Events);

const
  cTexts: array[TPublishedMembersText] of TAtlasText = (
    (De: 'default %s (implizit)'; En: 'default %s (implicit)'),
    (De: ' = `%s` (implizit)'; En: ' = `%s` (implicit)'),
    (De: 'Ereignisse'; En: 'Events'));

{$SCOPEDENUMS OFF}

const
  cBooleanTypes: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');
  cIntegerTypes: array[0..15] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt', 'Int64', 'Byte',
    'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt32');
  /// <summary>Höchstens so viele Aliase folgt die Ereigniserkennung.</summary>
  cMaxAliases = 8;

function ShortName(const AName: string): string;
begin
  // Qualifizierte Namen (Vcl.Controls.TControl) auf den Typnamen kürzen.
  Result := AName;
  if LastDelimiter('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function FindClass(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AIndex.FindSymbols(ShortName(AName)) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      ALocation := mLocation;
      Exit(True);
    end;
  end;
  Result := False;
end;

function FindTypeDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
    (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode.Children[mIndex].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
      TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
    begin
      Result := FindTypeDecl(ANode.Children[mIndex], AName);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
  Result := nil;
end;

/// <summary>Index des passenden ";" auf oberster Klammerebene ab AStart.</summary>
function DeclarationEnd(const AText: string; AStart: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AStart;
  while Result <= Length(AText) do
  begin
    case AText[Result] of
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
      ';':
        if mDepth = 0 then
        begin
          Exit;
        end;
      '''':
        begin
          Inc(Result);
          while (Result <= Length(AText)) and (AText[Result] <> '''') do
          begin
            Inc(Result);
          end;
        end;
    end;
    Inc(Result);
  end;
end;

type
  TWord = record
    Text: string;
    Start: Integer;
    Stop: Integer;
  end;

/// <summary>Bezeichner auf oberster Klammerebene ab AStart, ohne Strings.</summary>
function TopWords(const AText: string; AStart: Integer): TArray<TWord>;
var
  mIndex, mDepth, mFirst: Integer;
  mItem: TWord;
begin
  Result := nil;
  mDepth := 0;
  mIndex := AStart;
  while mIndex <= Length(AText) do
  begin
    case AText[mIndex] of
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
      '''':
        begin
          Inc(mIndex);
          while (mIndex <= Length(AText)) and (AText[mIndex] <> '''') do
          begin
            Inc(mIndex);
          end;
        end;
      'A'..'Z', 'a'..'z', '_':
        begin
          mFirst := mIndex;
          while (mIndex < Length(AText)) and CharInSet(AText[mIndex + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
          begin
            Inc(mIndex);
          end;
          if mDepth = 0 then
          begin
            mItem.Text := Copy(AText, mFirst, mIndex - mFirst + 1);
            mItem.Start := mFirst;
            mItem.Stop := mIndex + 1;
            Result := Result + [mItem];
          end;
        end;
    end;
    Inc(mIndex);
  end;
end;

type
  TSpecifiers = record
    DefaultKind: TPublishedDefaultKind;
    DefaultValue: string;
    Stored: string;
    /// <summary>"; default;" hinter einer Array-Property.</summary>
    ArrayDefault: Boolean;
  end;

const
  cSpecifierWords: array[0..9] of string = ('read', 'write', 'stored', 'default', 'nodefault', 'implements', 'index',
    'readonly', 'writeonly', 'dispid');

/// <summary>default, nodefault und stored aus "property Name…: Typ read … stored … default …; default;".</summary>
function ReadSpecifiers(const ADeclaration, AName: string): TSpecifiers;
var
  mWords: TArray<TWord>;
  mIndex, mNext, mStop, mStart, mFinish: Integer;
  mKeyword, mValue: string;
begin
  Result := Default(TSpecifiers);
  // Ab dem Namen: "Default" als Property-Name zählt nicht als Angabe.
  mStart := Pos(LowerCase(AName), LowerCase(ADeclaration));
  if mStart = 0 then
  begin
    mStart := 1;
  end;
  Inc(mStart, Length(AName));
  mStop := DeclarationEnd(ADeclaration, mStart);
  mWords := TopWords(Copy(ADeclaration, 1, mStop - 1), mStart);
  for mIndex := 0 to High(mWords) do
  begin
    mKeyword := LowerCase(mWords[mIndex].Text);
    if mKeyword = 'nodefault' then
    begin
      Result.DefaultKind := TPublishedDefaultKind.NoDefault;
      Continue;
    end;
    if (mKeyword <> 'default') and (mKeyword <> 'stored') then
    begin
      Continue;
    end;
    // Wert bis zur nächsten Angabe oder zum Ende.
    mNext := mIndex + 1;
    while (mNext <= High(mWords)) and (IndexText(mWords[mNext].Text, cSpecifierWords) < 0) do
    begin
      Inc(mNext);
    end;
    mFinish := mStop;
    if mNext <= High(mWords) then
    begin
      mFinish := mWords[mNext].Start;
    end;
    mValue := Trim(Copy(ADeclaration, mWords[mIndex].Stop, mFinish - mWords[mIndex].Stop));
    if mKeyword = 'stored' then
    begin
      Result.Stored := mValue;
    end
    else
    begin
      Result.DefaultKind := TPublishedDefaultKind.Explicit;
      Result.DefaultValue := mValue;
    end;
  end;
  mValue := Trim(Copy(ADeclaration, mStop + 1, MaxInt));
  Result.ArrayDefault := SameText(mValue, 'default;') or SameText(mValue, 'default');
end;

/// <summary>Text der Typdeklaration nach dem Namen bis zum ";" ("= procedure(Sender: TObject) of object").</summary>
function TypeDeclaration(const AIndex: ISymbolIndex; const AReadText: TMemberReadText; const ATypeName: string;
  out AKind: TIndexSymbolKind; out ADeclaration: string): Boolean;
var
  mLocation: TSymbolLocation;
  mText: string;
  mStart: Integer;
begin
  ADeclaration := '';
  AKind := TIndexSymbolKind.TypeAlias;
  if (AIndex = nil) or not Assigned(AReadText) then
  begin
    Exit(False);
  end;
  for mLocation in AIndex.FindSymbols(ShortName(ATypeName)) do
  begin
    if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind in [TIndexSymbolKind.TypeAlias,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.ObjectType]) and AReadText(mLocation.FileName, mText) then
    begin
      // 1-basierter Index im Text; Zeichen hinter dem Zeilenende zählen als Zeilenende.
      mStart := TLineTable.Build(mText).OffsetAt(mLocation.Symbol.SelectionRange.EndPos) + 1;
      ADeclaration := Trim(Copy(mText, mStart, DeclarationEnd(mText, mStart) - mStart));
      AKind := mLocation.Symbol.Kind;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>"= TNotifyEvent" bzw. "= type Vcl.Controls.TNotifyEvent" → Zielname; '' bei anderem Text.</summary>
function AliasTarget(const ADeclaration: string): string;
var
  mText: string;
  mIndex: Integer;
begin
  Result := '';
  mText := Trim(ADeclaration);
  if not StartsText('=', mText) then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, 2, MaxInt));
  if StartsText('type ', mText) then
  begin
    mText := Trim(Copy(mText, 6, MaxInt));
  end;
  for mIndex := 1 to Length(mText) do
  begin
    if not CharInSet(mText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit;
    end;
  end;
  Result := mText;
end;

class function TPublishedMembers.IsEventType(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const ATypeName: string): Boolean;
var
  mName, mDeclaration, mLower: string;
  mKind: TIndexSymbolKind;
  mStep: Integer;
begin
  mName := ATypeName;
  for mStep := 1 to cMaxAliases do
  begin
    if (mName = '') or not TypeDeclaration(AIndex, AReadText, mName, mKind, mDeclaration) then
    begin
      Break;
    end;
    if mKind <> TIndexSymbolKind.TypeAlias then
    begin
      Exit(False);
    end;
    mLower := LowerCase(mDeclaration);
    if EndsText('of object', mLower) or StartsText('reference to', Trim(Copy(mLower, 2, MaxInt))) then
    begin
      Exit(True);
    end;
    mName := AliasTarget(mDeclaration);
  end;
  // Typ nicht im Index (VCL ohne Quellen): nur das bekannte TNotifyEvent.
  Result := (mName <> '') and SameText(ShortName(mName), 'TNotifyEvent');
end;

/// <summary>Anfangswert eines eingebauten Typs: False oder 0; '' sonst.</summary>
function BuiltinDefault(const AName: string): string;
begin
  Result := '';
  if IndexText(ShortName(AName), cBooleanTypes) >= 0 then
  begin
    Result := 'False';
  end
  else if IndexText(ShortName(AName), cIntegerTypes) >= 0 then
  begin
    Result := '0';
  end;
end;

/// <summary>Erster Wert der Aufzählung "= (alNone, alTop, …)"; '' ohne.</summary>
function FirstEnumValue(const ADeclaration: string): string;
var
  mWords: TArray<TWord>;
begin
  Result := '';
  mWords := TopWords(Copy(ADeclaration, Pos('(', ADeclaration) + 1, MaxInt), 1);
  if Length(mWords) > 0 then
  begin
    Result := mWords[0].Text;
  end;
end;

/// <summary>Anfangswert eines Typs ohne default: False, 0 oder der erste Aufzählungswert; '' sonst.</summary>
function ImplicitDefault(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const ATypeName: string): string;
var
  mName, mDeclaration: string;
  mKind: TIndexSymbolKind;
  mStep: Integer;
begin
  Result := '';
  mName := ATypeName;
  for mStep := 0 to cMaxAliases do
  begin
    Result := BuiltinDefault(mName);
    if (Result <> '') or (mName = '') or not TypeDeclaration(AIndex, AReadText, mName, mKind, mDeclaration) then
    begin
      Exit;
    end;
    if mKind = TIndexSymbolKind.EnumType then
    begin
      Exit(FirstEnumValue(mDeclaration));
    end;
    if mKind <> TIndexSymbolKind.TypeAlias then
    begin
      Exit;
    end;
    mName := AliasTarget(mDeclaration);
  end;
end;

type
  TPropertyInfo = record
    TypeName: string;
    Specifiers: TSpecifiers;
    IsPublished: Boolean;
  end;

/// <summary>Properties der Klasse in Quelltextreihenfolge; AArrays: auch Array-Properties.</summary>
procedure ReadProperties(AClass: TSyntaxNode; const AText: string; AArrays: Boolean; ANames: TList<string>;
  AInfos: TDictionary<string, TPropertyInfo>; ADeclarations: TDictionary<string, string>);
var
  mIndex: Integer;
  mChild, mTypeNode: TSyntaxNode;
  mInPublished: Boolean;
  mInfo: TPropertyInfo;
  mKey, mDeclaration: string;
begin
  mInPublished := True;
  for mIndex := 0 to AClass.ChildCount - 1 do
  begin
    mChild := AClass.Children[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      mInPublished := SameText(mChild.Name, 'published');
    end
    else if (mChild.Kind = TSyntaxKind.PropertyDecl) and
      ((mChild.FindChild(TSyntaxKind.Parameters) = nil) = not AArrays) then
    begin
      mKey := LowerCase(mChild.Name);
      if AInfos.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mTypeNode := mChild.FindChild(TSyntaxKind.TypeReference);
      mInfo.TypeName := '';
      if mTypeNode <> nil then
      begin
        mInfo.TypeName := mTypeNode.Name;
      end;
      mDeclaration := Copy(AText, mChild.StartOffset + 1, mChild.EndOffset - mChild.StartOffset);
      mInfo.Specifiers := ReadSpecifiers(mDeclaration, mChild.Name);
      mInfo.IsPublished := mInPublished;
      ANames.Add(mChild.Name);
      AInfos.Add(mKey, mInfo);
      if ADeclarations <> nil then
      begin
        ADeclarations.AddOrSetValue(mKey, mDeclaration);
      end;
    end;
  end;
end;

/// <summary>Neues Mitglied AName aus AInfo, published in AClassName.</summary>
function NewMember(const AName: string; const AInfo: TPropertyInfo; const AClassName: string): TPublishedMember;
begin
  Result := Default(TPublishedMember);
  Result.Name := AName;
  Result.TypeName := AInfo.TypeName;
  Result.DefaultKind := AInfo.Specifiers.DefaultKind;
  Result.DefaultValue := AInfo.Specifiers.DefaultValue;
  Result.Stored := AInfo.Specifiers.Stored;
  Result.DeclaringClass := AClassName;
  Result.PublishedIn := AClassName;
end;

/// <summary>Ergänzt an AMember, was eine abgeleitete Klasse offen ließ. Die erste Deklaration mit Typ ist die
/// deklarierende Klasse.</summary>
procedure Supplement(var AMember: TPublishedMember; const AInfo: TPropertyInfo; const AClassName: string);
begin
  if (AMember.TypeName = '') and (AInfo.TypeName <> '') then
  begin
    AMember.TypeName := AInfo.TypeName;
    AMember.DeclaringClass := AClassName;
  end;
  if AMember.DefaultKind = TPublishedDefaultKind.None then
  begin
    AMember.DefaultKind := AInfo.Specifiers.DefaultKind;
    AMember.DefaultValue := AInfo.Specifiers.DefaultValue;
  end;
  if AMember.Stored = '' then
  begin
    AMember.Stored := AInfo.Specifiers.Stored;
  end;
end;

type
  /// <summary>Sammelt die published-Mitglieder einer Klasse und ihrer Vorfahren.</summary>
  TMemberCollect = class
  private
    FIndex: ISymbolIndex;
    FReadText: TMemberReadText;
    FMembers: TList<TPublishedMember>;
    FPositions: TDictionary<string, Integer>;
    FNames: TList<string>;
    FInfos: TDictionary<string, TPropertyInfo>;
    function ReadClass(const AClassName, AText: string): Boolean;
    procedure AddClassMembers(const AClassName: string);
    procedure AddImplicit(var AMember: TPublishedMember);
    procedure Complete;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TMemberReadText);
    destructor Destroy; override;
    function Run(const AClassName: string): TArray<TPublishedMember>;
  end;

constructor TMemberCollect.Create(const AIndex: ISymbolIndex; const AReadText: TMemberReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FMembers := TList<TPublishedMember>.Create;
  FPositions := TDictionary<string, Integer>.Create;
  FNames := TList<string>.Create;
  FInfos := TDictionary<string, TPropertyInfo>.Create;
end;

destructor TMemberCollect.Destroy;
begin
  FInfos.Free;
  FNames.Free;
  FPositions.Free;
  FMembers.Free;
  inherited;
end;

function TMemberCollect.ReadClass(const AClassName, AText: string): Boolean;
var
  mTree: TSyntaxTree;
  mDecl: TSyntaxNode;
begin
  FNames.Clear;
  FInfos.Clear;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mDecl := FindTypeDecl(mTree.Root, AClassName);
    Result := mDecl <> nil;
    if Result then
    begin
      ReadProperties(mDecl.FindChild(TSyntaxKind.ClassType), AText, False, FNames, FInfos, nil);
    end;
  finally
    mTree.Free;
  end;
end;

procedure TMemberCollect.AddClassMembers(const AClassName: string);
var
  mName, mKey: string;
  mInfo: TPropertyInfo;
  mIndex: Integer;
  mMember: TPublishedMember;
begin
  for mName in FNames do
  begin
    mKey := LowerCase(mName);
    mInfo := FInfos[mKey];
    if FPositions.TryGetValue(mKey, mIndex) then
    begin
      // Schon aus einer abgeleiteten Klasse bekannt: fehlende Angaben ergänzen.
      mMember := FMembers[mIndex];
      Supplement(mMember, mInfo, AClassName);
      FMembers[mIndex] := mMember;
    end
    else if mInfo.IsPublished then
    begin
      // Nicht published bleibt aus: In abgeleiteten Klassen kann sie noch published werden.
      FPositions.Add(mKey, FMembers.Count);
      FMembers.Add(NewMember(mName, mInfo, AClassName));
    end;
  end;
end;

procedure TMemberCollect.AddImplicit(var AMember: TPublishedMember);
begin
  AMember.DefaultValue := ImplicitDefault(FIndex, FReadText, AMember.TypeName);
  if AMember.DefaultValue <> '' then
  begin
    AMember.DefaultKind := TPublishedDefaultKind.Implicit;
  end;
end;

procedure TMemberCollect.Complete;
var
  mEvents: TDictionary<string, Boolean>;
  mIndex: Integer;
  mMember: TPublishedMember;
  mKey: string;
  mIsEvent: Boolean;
begin
  // Ereignis am Typ erkennen, implizite Vorgaben ergänzen.
  mEvents := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to FMembers.Count - 1 do
    begin
      mMember := FMembers[mIndex];
      mKey := LowerCase(mMember.TypeName);
      if not mEvents.TryGetValue(mKey, mIsEvent) then
      begin
        mIsEvent := (mMember.TypeName <> '') and
          TPublishedMembers.IsEventType(FIndex, FReadText, mMember.TypeName);
        mEvents.Add(mKey, mIsEvent);
      end;
      mMember.IsEvent := mIsEvent;
      if not mIsEvent and (mMember.DefaultKind = TPublishedDefaultKind.None) then
      begin
        AddImplicit(mMember);
      end;
      FMembers[mIndex] := mMember;
    end;
  finally
    mEvents.Free;
  end;
end;

function TMemberCollect.Run(const AClassName: string): TArray<TPublishedMember>;
var
  mLocation: TSymbolLocation;
  mClassName, mText: string;
  mDepth: Integer;
begin
  mClassName := AClassName;
  mDepth := 0;
  while (mClassName <> '') and (mDepth < TPublishedMembers.cMaxDepth) and
    FindClass(FIndex, mClassName, mLocation) and Assigned(FReadText) and FReadText(mLocation.FileName, mText) do
  begin
    Inc(mDepth);
    mClassName := mLocation.Symbol.Name;
    if not ReadClass(mClassName, mText) then
    begin
      Break;
    end;
    AddClassMembers(mClassName);
    if Length(mLocation.Symbol.Ancestors) = 0 then
    begin
      Break;
    end;
    mClassName := mLocation.Symbol.Ancestors[0];
  end;
  Complete;
  Result := FMembers.ToArray;
end;

class function TPublishedMembers.Collect(const AIndex: ISymbolIndex; const AClassName: string;
  const AReadText: TMemberReadText): TArray<TPublishedMember>;
var
  mCollect: TMemberCollect;
begin
  mCollect := TMemberCollect.Create(AIndex, AReadText);
  try
    Result := mCollect.Run(AClassName);
  finally
    mCollect.Free;
  end;
end;

/// <summary>"property Strings[Index: Integer]: string read Get; default;" → "Strings[Index: Integer]:
/// string".</summary>
function DefaultPropertyText(const ADeclaration: string): string;
var
  mWords: TArray<TWord>;
  mItem: TWord;
  mStop: Integer;
begin
  Result := Trim(ADeclaration);
  if StartsText('property', Result) then
  begin
    Result := Trim(Copy(Result, Length('property') + 1, MaxInt));
  end;
  mStop := DeclarationEnd(Result, 1);
  mWords := TopWords(Copy(Result, 1, mStop - 1), 1);
  for mItem in mWords do
  begin
    if IndexText(mItem.Text, cSpecifierWords) >= 0 then
    begin
      mStop := mItem.Start;
      Break;
    end;
  end;
  Result := Trim(Copy(Result, 1, mStop - 1));
end;

class function TPublishedMembers.DefaultProperty(const AIndex: ISymbolIndex; const AClassName: string;
  const AReadText: TMemberReadText): string;
var
  mLocation: TSymbolLocation;
  mClassName, mText, mName: string;
  mDepth: Integer;
  mTree: TSyntaxTree;
  mDecl: TSyntaxNode;
  mNames: TList<string>;
  mInfos: TDictionary<string, TPropertyInfo>;
  mDeclarations: TDictionary<string, string>;
begin
  Result := '';
  mNames := TList<string>.Create;
  mInfos := TDictionary<string, TPropertyInfo>.Create;
  mDeclarations := TDictionary<string, string>.Create;
  try
    mClassName := AClassName;
    mDepth := 0;
    while (mClassName <> '') and (mDepth < cMaxDepth) and FindClass(AIndex, mClassName, mLocation) and
      Assigned(AReadText) and AReadText(mLocation.FileName, mText) do
    begin
      Inc(mDepth);
      mTree := TSyntaxTreeCache.Parse(mText);
      try
        mDecl := FindTypeDecl(mTree.Root, mLocation.Symbol.Name);
        if mDecl = nil then
        begin
          Break;
        end;
        mNames.Clear;
        mInfos.Clear;
        mDeclarations.Clear;
        ReadProperties(mDecl.FindChild(TSyntaxKind.ClassType), mText, True, mNames, mInfos, mDeclarations);
      finally
        mTree.Free;
      end;
      for mName in mNames do
      begin
        if mInfos[LowerCase(mName)].Specifiers.ArrayDefault then
        begin
          Exit(DefaultPropertyText(mDeclarations[LowerCase(mName)]));
        end;
      end;
      if Length(mLocation.Symbol.Ancestors) = 0 then
      begin
        Break;
      end;
      mClassName := mLocation.Symbol.Ancestors[0];
    end;
  finally
    mDeclarations.Free;
    mInfos.Free;
    mNames.Free;
  end;
end;

/// <summary>"procedure(Sender: TObject) of object" → "(Sender: TObject)".</summary>
function TailOfType(const ADeclaration: string): string;
var
  mLower: string;
  mStart, mStop: Integer;
begin
  Result := '';
  mLower := LowerCase(ADeclaration);
  mStart := Pos('procedure', mLower);
  if mStart > 0 then
  begin
    Inc(mStart, Length('procedure'));
  end
  else
  begin
    mStart := Pos('function', mLower);
    if mStart = 0 then
    begin
      Exit;
    end;
    Inc(mStart, Length('function'));
  end;
  mStop := DeclarationEnd(ADeclaration, mStart);
  Result := Trim(Copy(ADeclaration, mStart, mStop - mStart));
  if EndsText('of object', Result) then
  begin
    Result := Trim(Copy(Result, 1, Length(Result) - Length('of object')));
  end;
end;

class function TPublishedMembers.EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const AComponentClass, AEventName: string; out ATail: string): Boolean;
var
  mMember: TPublishedMember;
  mTypeName, mDeclaration: string;
  mKind: TIndexSymbolKind;
begin
  ATail := '';
  mTypeName := '';
  if AIndex <> nil then
  begin
    for mMember in Collect(AIndex, AComponentClass, AReadText) do
    begin
      if SameText(mMember.Name, AEventName) then
      begin
        mTypeName := mMember.TypeName;
        Break;
      end;
    end;
  end;
  if mTypeName = '' then
  begin
    Exit(False);
  end;
  if TypeDeclaration(AIndex, AReadText, mTypeName, mKind, mDeclaration) then
  begin
    ATail := TailOfType(mDeclaration + ';');
    if ATail <> '' then
    begin
      Exit(True);
    end;
  end;
  if SameText(ShortName(mTypeName), 'TNotifyEvent') then
  begin
    ATail := cNotifyTail;
  end;
  Result := ATail <> '';
end;

class function TPublishedMembers.DefaultText(const AMember: TPublishedMember): string;
begin
  case AMember.DefaultKind of
    TPublishedDefaultKind.Explicit:
      Result := 'default ' + AMember.DefaultValue;
    TPublishedDefaultKind.Implicit:
      Result := cTexts[TPublishedMembersText.DefaultImplicit].Fmt([AMember.DefaultValue]);
    TPublishedDefaultKind.NoDefault:
      Result := 'nodefault';
  else
    Result := '';
  end;
  if AMember.Stored <> '' then
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + 'stored ' + AMember.Stored;
  end;
end;

function MemberLine(const AMember: TPublishedMember): string;
begin
  Result := '- `' + AMember.Name + '`';
  if AMember.TypeName <> '' then
  begin
    Result := Result + ': `' + AMember.TypeName + '`';
  end;
  case AMember.DefaultKind of
    TPublishedDefaultKind.Explicit:
      Result := Result + ' = `' + AMember.DefaultValue + '`';
    TPublishedDefaultKind.Implicit:
      Result := Result + cTexts[TPublishedMembersText.Implicit].Fmt([AMember.DefaultValue]);
    TPublishedDefaultKind.NoDefault:
      Result := Result + ' · nodefault';
    TPublishedDefaultKind.None: ;
  end;
  if AMember.Stored <> '' then
  begin
    Result := Result + ' · stored `' + AMember.Stored + '`';
  end;
end;

/// <summary>Deklarierende Klassen der Mitglieder (Ereignisse bei AEvents) in der Reihenfolge der Ableitung
/// (erstes Auftreten), klein geschrieben; ACount: Zahl der Mitglieder.</summary>
function SectionClasses(const AMembers: TArray<TPublishedMember>; AEvents: Boolean;
  out ACount: Integer): TArray<string>;
var
  mMember: TPublishedMember;
  mClasses: TList<string>;
begin
  ACount := 0;
  mClasses := TList<string>.Create;
  try
    for mMember in AMembers do
    begin
      if mMember.IsEvent = AEvents then
      begin
        Inc(ACount);
        if mClasses.IndexOf(LowerCase(mMember.DeclaringClass)) < 0 then
        begin
          mClasses.Add(LowerCase(mMember.DeclaringClass));
        end;
      end;
    end;
    Result := mClasses.ToArray;
  finally
    mClasses.Free;
  end;
end;

/// <summary>Block der Klasse AClass: Überschrift, dann je Mitglied eine Zeile oder (ACompact) die Namen.</summary>
function ClassBlock(const AMembers: TArray<TPublishedMember>; AEvents, ACompact: Boolean;
  const AClass: string): string;
var
  mMember: TPublishedMember;
  mNames: string;
begin
  Result := '';
  mNames := '';
  for mMember in AMembers do
  begin
    if (mMember.IsEvent = AEvents) and SameText(mMember.DeclaringClass, AClass) then
    begin
      if Result = '' then
      begin
        Result := #10#10 + '*' + mMember.DeclaringClass + '*';
      end;
      if not ACompact then
      begin
        Result := Result + #10 + MemberLine(mMember);
      end
      else if mNames = '' then
      begin
        mNames := mMember.Name;
      end
      else
      begin
        mNames := mNames + ', ' + mMember.Name;
      end;
    end;
  end;
  if ACompact then
  begin
    Result := Result + #10 + mNames;
  end;
end;

function Section(const ATitle: string; const AMembers: TArray<TPublishedMember>; AEvents, ACompact: Boolean): string;
var
  mClasses: TArray<string>;
  mClass: string;
  mCount: Integer;
begin
  // Nach deklarierender Klasse gruppiert.
  mClasses := SectionClasses(AMembers, AEvents, mCount);
  if mCount = 0 then
  begin
    Exit('');
  end;
  Result := Format('**%s** (%d)', [ATitle, mCount]);
  for mClass in mClasses do
  begin
    Result := Result + ClassBlock(AMembers, AEvents, ACompact, mClass);
  end;
end;

class function TPublishedMembers.ToMarkdown(const AMembers: TArray<TPublishedMember>): string;
begin
  Result := ToMarkdown(AMembers, '');
end;

class function TPublishedMembers.ToMarkdown(const AMembers: TArray<TPublishedMember>;
  const ADefaultProperty: string): string;
var
  mCompact: Boolean;
  mProperties, mEvents, mPart: string;
begin
  mCompact := Length(AMembers) > cCompactLimit;
  mProperties := Section('Published-Properties', AMembers, False, mCompact);
  mEvents := Section(cTexts[TPublishedMembersText.Events].Text, AMembers, True, mCompact);
  Result := '';
  if ADefaultProperty <> '' then
  begin
    Result := '**Standard-Property:** `' + ADefaultProperty + '`';
  end;
  for mPart in TArray<string>.Create(mProperties, mEvents) do
  begin
    if mPart <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + #10#10;
      end;
      Result := Result + mPart;
    end;
  end;
end;

const
  cKindNames: array[TPublishedDefaultKind] of string = ('', 'explicit', 'implicit', 'nodefault');

/// <summary>Setzt AKey auf AValue, wenn AValue nicht leer ist.</summary>
procedure AddText(AItem: TJSONObject; const AKey, AValue: string);
begin
  if AValue <> '' then
  begin
    AItem.AddPair(AKey, AValue);
  end;
end;

function MemberJson(const AMember: TPublishedMember): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AMember.Name);
  AddText(Result, 'type', AMember.TypeName);
  AddText(Result, 'default', AMember.DefaultValue);
  AddText(Result, 'defaultKind', cKindNames[AMember.DefaultKind]);
  AddText(Result, 'stored', AMember.Stored);
  AddText(Result, 'declaringClass', AMember.DeclaringClass);
  AddText(Result, 'publishedIn', AMember.PublishedIn);
  if AMember.IsEvent then
  begin
    Result.AddPair('event', TJSONTrue.Create);
  end;
end;

class function TPublishedMembers.ToJson(const AMembers: TArray<TPublishedMember>;
  const ADefaultProperty: string): TJSONObject;
var
  mMember: TPublishedMember;
  mItems: TJSONArray;
begin
  if (Length(AMembers) = 0) and (ADefaultProperty = '') then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  mItems := TJSONArray.Create;
  Result.AddPair('members', mItems);
  for mMember in AMembers do
  begin
    mItems.AddElement(MemberJson(mMember));
  end;
  AddText(Result, 'defaultProperty', ADefaultProperty);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.PublishedMembers', cTexts);

end.
