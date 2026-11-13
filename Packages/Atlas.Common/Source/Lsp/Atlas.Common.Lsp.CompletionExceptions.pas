unit Atlas.Common.Lsp.CompletionExceptions;

// Exception-Klassen (#483, ARG-085): Nach "raise " und nach "on Name: " bleiben nur Exception-Klassen
// (TNameResolver.Queries.ExceptionClassOf).
// - Nach raise: Projektklassen vor denen der Bibliotheken; Übernahme als "EFoo.Create('')" mit dem Cursor
//   zwischen den Anführungszeichen, dazu je Klasse ein eigener Eintrag "EFoo.CreateFmt('', [])".
// - Nach "on E: ": zuerst die Gruppe „Aus dem try-Block“ mit den Klassen, die die dort aufgerufenen Routinen laut
//   <exception cref> ihrer XMLDoc auslösen (#427), dazu bekannte Fälle der RTL ohne XMLDoc (StrToInt löst
//   EConvertError aus); darunter „Allgemein“. Klassen, die dasselbe except schon behandelt, fehlen. Stammt eine
//   Klasse von einer ab, die ein früherer Zweig behandelt, trägt sie die Warnung: Dieser Zweig würde nie erreicht.
// - Gesucht wird über die Tokens, damit es auch in noch unfertigem Code gilt; begin, try, case und asm öffnen
//   einen Block, end schließt ihn.
// - Abschaltbar mit completion.exceptionClasses; dann gilt die gewöhnliche Liste.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector;

type
  {$SCOPEDENUMS ON}
  TExceptionSiteKind = (None, Raise_, Handler);
  {$SCOPEDENUMS OFF}

  /// <summary>Stelle für Exception-Klassen und was das umgebende except schon behandelt.</summary>
  TExceptionSite = record
    Kind: TExceptionSiteKind;
    /// <summary>Bei Handler: Tokens des try-Blocks (TryFirst bis TryLast); -1 ohne.</summary>
    TryFirst: Integer;
    TryLast: Integer;
    /// <summary>Bei Handler: Klassen der Zweige davor bzw. aller übrigen Zweige desselben except (ohne Unit).
    /// </summary>
    Earlier: TArray<string>;
    Handled: TArray<string>;
  end;

  /// <summary>Bekannte Exception einer Routine der RTL ohne XMLDoc.</summary>
  TKnownRaise = record
    Routine: string;
    ClassName: string;
    UnitName: string;
  end;

  TCompletionExceptions = class
  public const
    /// <summary>Exception-Klassen, die schon ohne Eingabe aus nicht eingebundenen Units kommen.</summary>
    cCommonNames: array[0..6] of string = ('Exception', 'EConvertError', 'EArgumentException',
      'EArgumentOutOfRangeException', 'EInvalidOperation', 'EAbort', 'ENotSupportedException');
    /// <summary>Höchstzahl der Bezeichner im try-Block, die aufgelöst werden.</summary>
    cMaxCallees = 200;
    cGroupTry = 'try';
    cGroupGeneral = 'general';
    cGroupRaise = 'raise';
  public
    /// <summary>Stelle hinter dem Token ALast (raise bzw. ":" in "on E:"); False sonst.</summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer; out ASite: TExceptionSite): Boolean;
      static;
    /// <summary>Vorfilter für den Sammler: nur Exception-Klassen.</summary>
    class function Admit(AResolver: TNameResolver): TCompletionAdmitFunc; static;
    /// <summary>Bekannte Exceptions der RTL-Routine AName (ohne Unit, ohne Empfänger); nil ohne.</summary>
    class function KnownRaises(const AName: string): TArray<TKnownRaise>; static;
    /// <summary>Klassen (ohne Unit), die der try-Block von ASite laut XMLDoc bzw. KnownRaises auslösen kann, in der
    /// Reihenfolge der Aufrufe; dazu je Klasse die Unit aus KnownRaises in AUnits ('' sonst).</summary>
    class function TryClasses(ARequest: TCompletionRequest; const ASite: TExceptionSite;
      out AUnits: TArray<string>): TArray<string>; static;
    /// <summary>Nur Exception-Klassen, sortiert und mit Gruppen bzw. Übernahmetext (siehe oben).</summary>
    class function Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext; ASnippets: Boolean;
      const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionGenerics;

const
  cKnownRaiseTable: array[0..19] of TKnownRaise = (
    (Routine: 'StrToInt'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToInt64'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToUInt'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToUInt64'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToFloat'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToCurr'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToDate'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToTime'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToDateTime'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StrToBool'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'StringToGUID'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'EncodeDate'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'EncodeTime'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'Format'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'FmtStr'; ClassName: 'EConvertError'; UnitName: 'System.SysUtils'),
    (Routine: 'Abort'; ClassName: 'EAbort'; UnitName: 'System.SysUtils'),
    (Routine: 'Assert'; ClassName: 'EAssertionFailed'; UnitName: 'System.SysUtils'),
    (Routine: 'RaiseLastOSError'; ClassName: 'EOSError'; UnitName: 'System.SysUtils'),
    (Routine: 'LoadFromFile'; ClassName: 'EFOpenError'; UnitName: 'System.Classes'),
    (Routine: 'SaveToFile'; ClassName: 'EFCreateError'; UnitName: 'System.Classes'));

function NextSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

/// <summary>Öffnet ein Block, der mit end schließt?</summary>
function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm');
end;

/// <summary>Rückwärts ab AFrom (ausschließlich) das Schlüsselwort AWord auf derselben Blockebene; -1, wenn vorher
/// ein Block der Ebene beginnt.</summary>
function BackTo(const ATokens: TArray<TPascalToken>; AFrom: Integer; const AWord: string): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := PreviousCode(ATokens, AFrom);
  while Result >= 0 do
  begin
    if ATokens[Result].IsKeyword('end') then
    begin
      Inc(mDepth);
    end
    else if (mDepth = 0) and ATokens[Result].IsKeyword(AWord) then
    begin
      Exit;
    end
    else if OpensBlock(ATokens[Result]) then
    begin
      if mDepth = 0 then
      begin
        Exit(-1);
      end;
      Dec(mDepth);
    end;
    Result := PreviousCode(ATokens, Result);
  end;
end;

/// <summary>Klasse eines Zweigs "on [E:] A.B do" ab dem Token on an AOn (ohne Unit); '' ohne.</summary>
function HandlerClass(const ATokens: TArray<TPascalToken>; AOn: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := NextSignificant(ATokens, AOn);
  if (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    (NextSignificant(ATokens, mIndex) <= High(ATokens)) and ATokens[NextSignificant(ATokens, mIndex)].IsSymbol(':') then
  begin
    mIndex := NextSignificant(ATokens, NextSignificant(ATokens, mIndex));
  end;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := ATokens[mIndex].Text;
    mIndex := NextSignificant(ATokens, mIndex);
    if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := NextSignificant(ATokens, mIndex);
  end;
  if (mIndex > High(ATokens)) or not ATokens[mIndex].IsKeyword('do') then
  begin
    Result := '';
  end;
end;

/// <summary>Steht ALast auf dem ":" in "on E:"? AOn ist dann die Stelle des on.</summary>
function IsHandlerColon(const ATokens: TArray<TPascalToken>; ALast: Integer; out AOn: Integer): Boolean;
var
  mName: Integer;
begin
  mName := PreviousCode(ATokens, ALast);
  AOn := PreviousCode(ATokens, mName);
  Result := ATokens[ALast].IsSymbol(':') and (mName >= 0) and (ATokens[mName].Kind = TPascalTokenKind.Identifier) and
    (AOn >= 0) and IsWord(ATokens[AOn], 'on');
end;

/// <summary>Klasse des Zweigs mit on an AIndex in ASite vermerken; vor AOn auch als früheren Zweig.</summary>
procedure AddBranch(const ATokens: TArray<TPascalToken>; AIndex, AOn: Integer; var ASite: TExceptionSite);
var
  mName: string;
begin
  mName := HandlerClass(ATokens, AIndex);
  if mName = '' then
  begin
    Exit;
  end;
  ASite.Handled := ASite.Handled + [mName];
  if AIndex < AOn then
  begin
    ASite.Earlier := ASite.Earlier + [mName];
  end;
end;

/// <summary>Zweige desselben except: "on" auf der Ebene des except bis zu seinem end; der Zweig an AOn nicht.
/// </summary>
procedure CollectBranches(const ATokens: TArray<TPascalToken>; AExcept, AOn: Integer; var ASite: TExceptionSite);
var
  mDepth, mIndex: Integer;
begin
  mDepth := 0;
  mIndex := NextSignificant(ATokens, AExcept);
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('end') then
    begin
      if mDepth = 0 then
      begin
        Break;
      end;
      Dec(mDepth);
    end
    else if OpensBlock(ATokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if (mDepth = 0) and (mIndex <> AOn) and IsWord(ATokens[mIndex], 'on') then
    begin
      AddBranch(ATokens, mIndex, AOn, ASite);
    end;
    mIndex := NextSignificant(ATokens, mIndex);
  end;
end;

{ TCompletionExceptions }

class function TCompletionExceptions.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer;
  out ASite: TExceptionSite): Boolean;
var
  mOn, mExcept, mTry: Integer;
begin
  ASite := Default(TExceptionSite);
  ASite.TryFirst := -1;
  ASite.TryLast := -1;
  Result := False;
  if (ALast < 0) or (ALast > High(ATokens)) then
  begin
    Exit;
  end;
  if ATokens[ALast].IsKeyword('raise') then
  begin
    ASite.Kind := TExceptionSiteKind.Raise_;
    Exit(True);
  end;
  // "on E: |"
  if not IsHandlerColon(ATokens, ALast, mOn) then
  begin
    Exit;
  end;
  mExcept := BackTo(ATokens, mOn, 'except');
  Result := mExcept >= 0;
  if Result then
  begin
    mTry := BackTo(ATokens, mExcept, 'try');
    ASite.Kind := TExceptionSiteKind.Handler;
    if mTry >= 0 then
    begin
      ASite.TryFirst := mTry + 1;
      ASite.TryLast := mExcept - 1;
    end;
    CollectBranches(ATokens, mExcept, mOn, ASite);
  end;
end;

class function TCompletionExceptions.Admit(AResolver: TNameResolver): TCompletionAdmitFunc;
begin
  Result :=
    function(const ASymbol: TResolvedSymbol): Boolean
    var
      ExceptionClass: TResolvedSymbol;
    begin
      Result := AResolver.Queries.ExceptionClassOf(ASymbol, ExceptionClass);
    end;
end;

class function TCompletionExceptions.KnownRaises(const AName: string): TArray<TKnownRaise>;
var
  mKnown: TKnownRaise;
begin
  Result := nil;
  for mKnown in cKnownRaiseTable do
  begin
    if SameText(mKnown.Routine, AName) then
    begin
      Result := Result + [mKnown];
    end;
  end;
end;

type
  /// <summary>Sucht die Exceptions der Aufrufe im try-Block (TCompletionExceptions.TryClasses).</summary>
  TTryScan = record
    Request: TCompletionRequest;
    Reader: TDocReadText;
    // Klassen (groß) und Deklarationen (Datei:Zeile), die schon gezählt sind.
    Seen, Done: TDictionary<string, Boolean>;
    // Zeilen je Datei (groß), nil ohne Quelltext.
    Lines: TDictionary<string, TArray<string>>;
    Classes, Units: TArray<string>;
    procedure AddClass(const AName, AUnit: string);
    function FileLines(const AFileName: string): TArray<string>;
    /// <summary>Die Klassen aus &lt;exception cref&gt; der Routine ASymbol, je Deklaration einmal.</summary>
    procedure AddDocumented(const ASymbol: TResolvedSymbol);
    /// <summary>Der Aufruf am Token AIndex: XMLDoc und bekannte Fälle der RTL.</summary>
    procedure AddCall(const ATokens: TArray<TPascalToken>; AIndex: Integer);
  end;

procedure TTryScan.AddClass(const AName, AUnit: string);
var
  mPlain: string;
begin
  mPlain := Copy(AName, LastDelimiter('.:', AName) + 1, MaxInt);
  if (mPlain = '') or Seen.ContainsKey(UpperCase(mPlain)) then
  begin
    Exit;
  end;
  Seen.Add(UpperCase(mPlain), True);
  Classes := Classes + [mPlain];
  Units := Units + [AUnit];
end;

function TTryScan.FileLines(const AFileName: string): TArray<string>;
var
  mText: string;
begin
  if Lines.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if Assigned(Reader) and Reader(AFileName, mText) then
  begin
    Result := TLspDocumentation.SplitLines(mText);
  end;
  Lines.Add(UpperCase(AFileName), Result);
end;

procedure TTryScan.AddDocumented(const ASymbol: TResolvedSymbol);
var
  mKey: string;
  mFileLines: TArray<string>;
  mDoc: TXmlDoc;
  mEntry: TXmlDocEntry;
begin
  mKey := UpperCase(ASymbol.FileName) + ':' + IntToStr(ASymbol.Range.StartPos.Line);
  if Done.ContainsKey(mKey) then
  begin
    Exit;
  end;
  Done.Add(mKey, True);
  mFileLines := FileLines(ASymbol.FileName);
  if mFileLines = nil then
  begin
    Exit;
  end;
  mDoc := TLspDocumentation.Load(Request.Resolver, ASymbol, mFileLines, ASymbol.Range.StartPos.Line, Reader);
  for mEntry in mDoc.Exceptions do
  begin
    AddClass(mEntry.Name, '');
  end;
end;

/// <summary>Routine mit Quelle (Routine, Methode, Konstruktor)?</summary>
function IsRoutineSymbol(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := ASymbol.Found and (ASymbol.SymbolKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method,
    TIndexSymbolKind.Constructor_]) and (ASymbol.FileName <> '');
end;

procedure TTryScan.AddCall(const ATokens: TArray<TPascalToken>; AIndex: Integer);
var
  mSymbol: TResolvedSymbol;
  mFromLibrary: Boolean;
  mDeclaringUnit: TUnitIndex;
  mKnown: TKnownRaise;
begin
  mFromLibrary := True;
  mSymbol := Request.Resolver.Resolve(Request.Tree, Request.FileName, ATokens[AIndex].StartPos);
  if IsRoutineSymbol(mSymbol) then
  begin
    mFromLibrary := not Request.Resolver.DeclaringUnit(mSymbol, mDeclaringUnit) or mDeclaringUnit.Library_;
    AddDocumented(mSymbol);
  end;
  // Bekannte Fälle der RTL, deren Quelltext keine XMLDoc hat; eine eigene Routine gleichen Namens zählt nicht.
  if mFromLibrary then
  begin
    for mKnown in TCompletionExceptions.KnownRaises(ATokens[AIndex].Text) do
    begin
      AddClass(mKnown.ClassName, mKnown.UnitName);
    end;
  end;
end;

/// <summary>Kann das Token AIndex ein Aufruf sein? Zuweisungsziele und Deklarationen rufen nichts auf.</summary>
function IsCallee(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := NextSignificant(ATokens, AIndex);
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    not ((mNext <= High(ATokens)) and (ATokens[mNext].IsSymbol(':=') or ATokens[mNext].IsSymbol(':')));
end;

class function TCompletionExceptions.TryClasses(ARequest: TCompletionRequest; const ASite: TExceptionSite;
  out AUnits: TArray<string>): TArray<string>;
var
  mTokens: TArray<TPascalToken>;
  mScan: TTryScan;
  mIndex, mCount: Integer;
begin
  Result := nil;
  AUnits := nil;
  if (ASite.TryFirst < 0) or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit;
  end;
  mTokens := ARequest.Tree.Tokens;
  mScan := Default(TTryScan);
  mScan.Request := ARequest;
  mScan.Reader := TLspDocumentation.Reader(ARequest.FileName, ARequest.Text, ARequest.ReadText);
  mScan.Seen := TDictionary<string, Boolean>.Create;
  mScan.Done := TDictionary<string, Boolean>.Create;
  mScan.Lines := TDictionary<string, TArray<string>>.Create;
  try
    mCount := 0;
    for mIndex := ASite.TryFirst to Min(ASite.TryLast, High(mTokens)) do
    begin
      if not IsCallee(mTokens, mIndex) then
      begin
        Continue;
      end;
      Inc(mCount);
      if mCount > cMaxCallees then
      begin
        Break;
      end;
      mScan.AddCall(mTokens, mIndex);
    end;
    Result := mScan.Classes;
    AUnits := mScan.Units;
  finally
    mScan.Lines.Free;
    mScan.Done.Free;
    mScan.Seen.Free;
  end;
end;

type
  TExceptionEntry = record
    Item: TCompletionItem;
    Key: string;
    /// <summary>Kleiner ist besser: 0 eingebunden, 1 Alias aus anderer Unit, 2 Original aus anderer Unit.</summary>
    Preference: Integer;
    Library_: Boolean;
    /// <summary>Stelle in der Liste des try-Blocks, -1 sonst.</summary>
    TryRank: Integer;
    Order: Integer;
  end;

  /// <summary>Gesammelte Einträge, je Klasse (Key) einer.</summary>
  TExceptionEntries = record
    Items: TList<TExceptionEntry>;
    ByKey: TDictionary<string, Integer>;
    Order: Integer;
    /// <summary>Bei gleicher Klasse gewinnt der Eintrag mit kleinerer Preference und behält die Stelle.</summary>
    procedure Add(AEntry: TExceptionEntry);
    /// <summary>Klasse aus dem try-Block, die die Liste nicht kennt (z. B. ohne Quellen der RTL im Index).
    /// </summary>
    procedure AddTryClass(const AName, AUnit: string; ARank: Integer);
    function HasName(const AName: string): Boolean;
  end;

function IndexOfText(const AName: string; const AList: TArray<string>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if SameText(AList[mIndex], AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TExceptionEntries.Add(AEntry: TExceptionEntry);
var
  mExisting: Integer;
begin
  AEntry.Order := Order;
  Inc(Order);
  if not ByKey.TryGetValue(AEntry.Key, mExisting) then
  begin
    ByKey.Add(AEntry.Key, Items.Count);
    Items.Add(AEntry);
  end
  else if AEntry.Preference < Items[mExisting].Preference then
  begin
    AEntry.Order := Items[mExisting].Order;
    Items[mExisting] := AEntry;
  end;
end;

procedure TExceptionEntries.AddTryClass(const AName, AUnit: string; ARank: Integer);
var
  mEntry: TExceptionEntry;
begin
  mEntry := Default(TExceptionEntry);
  mEntry.Item.Name := AName;
  mEntry.Item.Kind := cKindClass;
  mEntry.Item.Detail := AUnit;
  mEntry.Library_ := True;
  mEntry.TryRank := ARank;
  mEntry.Order := Order;
  Inc(Order);
  Items.Add(mEntry);
end;

function TExceptionEntries.HasName(const AName: string): Boolean;
var
  mEntry: TExceptionEntry;
begin
  for mEntry in Items do
  begin
    if SameText(mEntry.Item.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function PreferenceOf(const AItem: TCompletionItem; const ASymbol: TResolvedSymbol): Integer;
begin
  if Length(AItem.AdditionalEdits) = 0 then
  begin
    Result := 0;
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    Result := 1;
  end
  else
  begin
    Result := 2;
  end;
end;

/// <summary>Reihenfolge der Zweige: Ein früherer Zweig (AEarlier) fängt schon alle Nachfahren seiner Klasse.
/// Dessen Klasse, '' sonst.</summary>
function UnreachableBy(AResolver: TNameResolver; const AExceptionClass: TResolvedSymbol;
  const AEarlier: TArray<string>): string;
var
  mAncestors: TArray<string>;
  mEarlier: string;
begin
  Result := '';
  mAncestors := AResolver.Queries.AncestorNames(AExceptionClass);
  for mEarlier in AEarlier do
  begin
    if IndexOfText(mEarlier, mAncestors) > 0 then
    begin
      Exit(mEarlier);
    end;
  end;
end;

/// <summary>Eintrag für AItem, wenn er eine Exception-Klasse ist, die das except noch nicht behandelt.</summary>
function EntryOf(ARequest: TCompletionRequest; AUnits: TDictionary<string, TUnitIndex>; const AItem: TCompletionItem;
  const ASite: TExceptionSite; const ATryNames: TArray<string>; out AEntry: TExceptionEntry): Boolean;
var
  mSymbol, mExceptionClass: TResolvedSymbol;
  mDeclaringUnit: TUnitIndex;
  mUnreachable: string;
begin
  AEntry := Default(TExceptionEntry);
  Result := TCompletionGenerics.ItemSymbol(ARequest, AUnits, AItem, mSymbol) and
    ARequest.Resolver.Queries.ExceptionClassOf(mSymbol, mExceptionClass) and
      (IndexOfText(AItem.Name, ASite.Handled) < 0);
  if not Result then
  begin
    Exit;
  end;
  AEntry.Item := AItem;
  AEntry.Key := UpperCase(mExceptionClass.UnitName + '.' + mExceptionClass.QualifiedName);
  AEntry.Preference := PreferenceOf(AItem, mSymbol);
  AEntry.Library_ := ARequest.Resolver.DeclaringUnit(mExceptionClass, mDeclaringUnit) and mDeclaringUnit.Library_;
  AEntry.TryRank := IndexOfText(AItem.Name, ATryNames);
  mUnreachable := UnreachableBy(ARequest.Resolver, mExceptionClass, ASite.Earlier);
  if mUnreachable <> '' then
  begin
    AEntry.Item.Unreachable := mUnreachable;
  end;
end;

/// <summary>try-Block nach seiner Reihenfolge, dann Projekt vor Bibliothek, dann wie gesammelt; Order macht es
/// eindeutig.</summary>
function CompareEntries(const A, B: TExceptionEntry): Integer;
begin
  if (A.TryRank >= 0) <> (B.TryRank >= 0) then
  begin
    Result := IfThen(A.TryRank >= 0, -1, 1);
  end
  else if (A.TryRank >= 0) and (A.TryRank <> B.TryRank) then
  begin
    Result := A.TryRank - B.TryRank;
  end
  else if A.Library_ <> B.Library_ then
  begin
    Result := IfThen(B.Library_, -1, 1);
  end
  else
  begin
    Result := A.Order - B.Order;
  end;
end;

function SortedEntries(AEntries: TList<TExceptionEntry>): TArray<TExceptionEntry>;
begin
  Result := AEntries.ToArray;
  TArray.Sort<TExceptionEntry>(Result, TComparer<TExceptionEntry>.Construct(
    function(const A, B: TExceptionEntry): Integer
    begin
      Result := CompareEntries(A, B);
    end));
end;

/// <summary>raise EFoo.Create('|'), daneben EFoo.CreateFmt('|', []).</summary>
function RaiseItems(const AItem: TCompletionItem; ASnippets: Boolean): TArray<TCompletionItem>;
var
  mItem, mFmt: TCompletionItem;
begin
  mItem := AItem;
  mItem.ExceptionGroup := TCompletionExceptions.cGroupRaise;
  mItem.FilterText := mItem.Name;
  mFmt := mItem;
  mItem.Snippet := ASnippets;
  mFmt.Snippet := ASnippets;
  mFmt.Name := mItem.Name + '.CreateFmt';
  mFmt.Kind := cKindConstructor;
  if ASnippets then
  begin
    mItem.InsertText := mItem.Name + '.Create(''$0'')';
    mFmt.InsertText := mItem.Name + '.CreateFmt(''$1'', [$2])$0';
  end
  else
  begin
    mItem.InsertText := mItem.Name + '.Create('''')';
    mFmt.InsertText := mItem.Name + '.CreateFmt('''', [])';
  end;
  Result := [mItem, mFmt];
end;

/// <summary>Gruppen „Aus dem try-Block“ und „Allgemein“ über den erwarteten Typ (#417), wenn AAnyTry.</summary>
function HandlerItem(const AEntry: TExceptionEntry; AAnyTry: Boolean): TCompletionItem;
begin
  Result := AEntry.Item;
  if not AAnyTry then
  begin
    Exit;
  end;
  Result.Expected := 'Exception';
  Result.Fits := AEntry.TryRank >= 0;
  Result.ExceptionGroup := TCompletionExceptions.cGroupGeneral;
  if Result.Fits then
  begin
    Result.ExceptionGroup := TCompletionExceptions.cGroupTry;
  end;
end;

/// <summary>Die Einträge für die Stelle der Art AKind.</summary>
function ItemsOf(const ASorted: TArray<TExceptionEntry>; AKind: TExceptionSiteKind;
  ASnippets: Boolean): TArray<TCompletionItem>;
var
  mEntry: TExceptionEntry;
  mAnyTry: Boolean;
begin
  mAnyTry := False;
  for mEntry in ASorted do
  begin
    mAnyTry := mAnyTry or (mEntry.TryRank >= 0);
  end;
  Result := nil;
  for mEntry in ASorted do
  begin
    if AKind = TExceptionSiteKind.Raise_ then
    begin
      Result := Result + RaiseItems(mEntry.Item, ASnippets);
    end
    else
    begin
      Result := Result + [HandlerItem(mEntry, mAnyTry)];
    end;
  end;
end;

class function TCompletionExceptions.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ASnippets: Boolean; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mSite: TExceptionSite;
  mTryNames, mTryUnits: TArray<string>;
  mUnits: TDictionary<string, TUnitIndex>;
  mEntries: TExceptionEntries;
  mItem: TCompletionItem;
  mEntry: TExceptionEntry;
  mRank: Integer;
begin
  Result := AItems;
  if not SiteAt(ARequest.Tree.Tokens, AContext.ExceptionToken, mSite) then
  begin
    Exit;
  end;
  mTryNames := nil;
  mTryUnits := nil;
  if mSite.Kind = TExceptionSiteKind.Handler then
  begin
    mTryNames := TryClasses(ARequest, mSite, mTryUnits);
  end;
  mUnits := TDictionary<string, TUnitIndex>.Create;
  mEntries := Default(TExceptionEntries);
  mEntries.ByKey := TDictionary<string, Integer>.Create;
  mEntries.Items := TList<TExceptionEntry>.Create;
  try
    for mItem in AItems do
    begin
      if EntryOf(ARequest, mUnits, mItem, mSite, mTryNames, mEntry) then
      begin
        mEntries.Add(mEntry);
      end;
    end;
    for mRank := 0 to High(mTryNames) do
    begin
      if not mEntries.HasName(mTryNames[mRank]) and (IndexOfText(mTryNames[mRank], mSite.Handled) < 0) and
        (MatchScore(mTryNames[mRank], AContext.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
      begin
        mEntries.AddTryClass(mTryNames[mRank], mTryUnits[mRank], mRank);
      end;
    end;
    Result := ItemsOf(SortedEntries(mEntries.Items), mSite.Kind, ASnippets);
  finally
    mEntries.Items.Free;
    mEntries.ByKey.Free;
    mUnits.Free;
  end;
end;

end.
