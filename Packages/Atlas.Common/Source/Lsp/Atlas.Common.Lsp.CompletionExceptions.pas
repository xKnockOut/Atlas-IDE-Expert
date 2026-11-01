unit Atlas.Common.Lsp.CompletionExceptions;

// Exception-Klassen (#483, ARG-085): Nach "raise " und nach "on Name: " bleiben nur Exception-Klassen
// (TNameResolver.ExceptionClassOf).
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
    CommonNames: array[0..6] of string = ('Exception', 'EConvertError', 'EArgumentException',
      'EArgumentOutOfRangeException', 'EInvalidOperation', 'EAbort', 'ENotSupportedException');
    /// <summary>Höchstzahl der Bezeichner im try-Block, die aufgelöst werden.</summary>
    MaxCallees = 200;
    GroupTry = 'try';
    GroupGeneral = 'general';
    GroupRaise = 'raise';
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
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionGenerics;

const
  KnownRaiseTable: array[0..19] of TKnownRaise = (
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

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

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
  Depth: Integer;
begin
  Depth := 0;
  Result := PreviousSignificant(ATokens, AFrom);
  while Result >= 0 do
  begin
    if ATokens[Result].IsKeyword('end') then
    begin
      Inc(Depth);
    end
    else if (Depth = 0) and ATokens[Result].IsKeyword(AWord) then
    begin
      Exit;
    end
    else if OpensBlock(ATokens[Result]) then
    begin
      if Depth = 0 then
      begin
        Exit(-1);
      end;
      Dec(Depth);
    end;
    Result := PreviousSignificant(ATokens, Result);
  end;
end;

/// <summary>Klasse eines Zweigs "on [E:] A.B do" ab dem Token on an AOn (ohne Unit); '' ohne.</summary>
function HandlerClass(const ATokens: TArray<TPascalToken>; AOn: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  Index := NextSignificant(ATokens, AOn);
  if (Index <= High(ATokens)) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
    (NextSignificant(ATokens, Index) <= High(ATokens)) and ATokens[NextSignificant(ATokens, Index)].IsSymbol(':') then
  begin
    Index := NextSignificant(ATokens, NextSignificant(ATokens, Index));
  end;
  while (Index <= High(ATokens)) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := ATokens[Index].Text;
    Index := NextSignificant(ATokens, Index);
    if (Index > High(ATokens)) or not ATokens[Index].IsSymbol('.') then
    begin
      Break;
    end;
    Index := NextSignificant(ATokens, Index);
  end;
  if (Index > High(ATokens)) or not ATokens[Index].IsKeyword('do') then
  begin
    Result := '';
  end;
end;

{ TCompletionExceptions }

class function TCompletionExceptions.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer;
  out ASite: TExceptionSite): Boolean;
var
  NameIndex, OnIndex, ExceptIndex, TryIndex, Index, Depth: Integer;
  Name: string;
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
  if not ATokens[ALast].IsSymbol(':') then
  begin
    Exit;
  end;
  NameIndex := PreviousSignificant(ATokens, ALast);
  OnIndex := PreviousSignificant(ATokens, NameIndex);
  if (NameIndex < 0) or (ATokens[NameIndex].Kind <> TPascalTokenKind.Identifier) or (OnIndex < 0) or
    not IsWord(ATokens[OnIndex], 'on') then
  begin
    Exit;
  end;
  ExceptIndex := BackTo(ATokens, OnIndex, 'except');
  if ExceptIndex < 0 then
  begin
    Exit;
  end;
  TryIndex := BackTo(ATokens, ExceptIndex, 'try');
  ASite.Kind := TExceptionSiteKind.Handler;
  if TryIndex >= 0 then
  begin
    ASite.TryFirst := TryIndex + 1;
    ASite.TryLast := ExceptIndex - 1;
  end;
  // Zweige desselben except: "on" auf der Ebene des except bis zu seinem end.
  Depth := 0;
  Index := NextSignificant(ATokens, ExceptIndex);
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('end') then
    begin
      if Depth = 0 then
      begin
        Break;
      end;
      Dec(Depth);
    end
    else if OpensBlock(ATokens[Index]) then
    begin
      Inc(Depth);
    end
    else if (Depth = 0) and (Index <> OnIndex) and IsWord(ATokens[Index], 'on') then
    begin
      Name := HandlerClass(ATokens, Index);
      if Name <> '' then
      begin
        ASite.Handled := ASite.Handled + [Name];
        if Index < OnIndex then
        begin
          ASite.Earlier := ASite.Earlier + [Name];
        end;
      end;
    end;
    Index := NextSignificant(ATokens, Index);
  end;
  Result := True;
end;

class function TCompletionExceptions.Admit(AResolver: TNameResolver): TCompletionAdmitFunc;
begin
  Result :=
    function(const ASymbol: TResolvedSymbol): Boolean
    var
      ExceptionClass: TResolvedSymbol;
    begin
      Result := AResolver.ExceptionClassOf(ASymbol, ExceptionClass);
    end;
end;

class function TCompletionExceptions.KnownRaises(const AName: string): TArray<TKnownRaise>;
var
  Known: TKnownRaise;
begin
  Result := nil;
  for Known in KnownRaiseTable do
  begin
    if SameText(Known.Routine, AName) then
    begin
      Result := Result + [Known];
    end;
  end;
end;

class function TCompletionExceptions.TryClasses(ARequest: TCompletionRequest; const ASite: TExceptionSite;
  out AUnits: TArray<string>): TArray<string>;
var
  Tokens: TArray<TPascalToken>;
  Seen, Done: TDictionary<string, Boolean>;
  Lines: TDictionary<string, TArray<string>>;
  Reader: TDocReadText;
  Index, Count, Next: Integer;
  Symbol: TResolvedSymbol;
  Doc: TXmlDoc;
  Entry: TXmlDocEntry;
  Known: TKnownRaise;
  Text, Key: string;
  FileLines: TArray<string>;
  FromLibrary: Boolean;
  DeclaringUnit: TUnitIndex;

  procedure AddClass(const AName, AUnit: string);
  var
    Plain: string;
  begin
    Plain := Copy(AName, LastDelimiter('.:', AName) + 1, MaxInt);
    if (Plain = '') or Seen.ContainsKey(UpperCase(Plain)) then
    begin
      Exit;
    end;
    Seen.Add(UpperCase(Plain), True);
    Result := Result + [Plain];
    AUnits := AUnits + [AUnit];
  end;

begin
  Result := nil;
  AUnits := nil;
  if (ASite.TryFirst < 0) or (ARequest.Tree = nil) or (ARequest.Resolver = nil) then
  begin
    Exit;
  end;
  Tokens := ARequest.Tree.Tokens;
  Reader := TLspDocumentation.Reader(ARequest.FileName, ARequest.Text, ARequest.ReadText);
  Seen := TDictionary<string, Boolean>.Create;
  Done := TDictionary<string, Boolean>.Create;
  Lines := TDictionary<string, TArray<string>>.Create;
  try
    Count := 0;
    for Index := ASite.TryFirst to Min(ASite.TryLast, High(Tokens)) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      // Zuweisungsziele und Deklarationen rufen nichts auf.
      Next := NextSignificant(Tokens, Index);
      if (Next <= High(Tokens)) and (Tokens[Next].IsSymbol(':=') or Tokens[Next].IsSymbol(':')) then
      begin
        Continue;
      end;
      Inc(Count);
      if Count > MaxCallees then
      begin
        Break;
      end;
      FromLibrary := True;
      Symbol := ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName, Tokens[Index].StartPos);
      if Symbol.Found and (Symbol.SymbolKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method,
        TIndexSymbolKind.Constructor_]) and (Symbol.FileName <> '') then
      begin
        FromLibrary := not ARequest.Resolver.DeclaringUnit(Symbol, DeclaringUnit) or DeclaringUnit.Library_;
        Key := UpperCase(Symbol.FileName) + ':' + IntToStr(Symbol.Range.StartPos.Line);
        if not Done.ContainsKey(Key) then
        begin
          Done.Add(Key, True);
          if not Lines.TryGetValue(UpperCase(Symbol.FileName), FileLines) then
          begin
            FileLines := nil;
            if Reader(Symbol.FileName, Text) then
            begin
              FileLines := TLspDocumentation.SplitLines(Text);
            end;
            Lines.Add(UpperCase(Symbol.FileName), FileLines);
          end;
          if FileLines <> nil then
          begin
            Doc := TLspDocumentation.Load(ARequest.Resolver, Symbol, FileLines, Symbol.Range.StartPos.Line, Reader);
            for Entry in Doc.Exceptions do
            begin
              AddClass(Entry.Name, '');
            end;
          end;
        end;
      end;
      // Bekannte Fälle der RTL, deren Quelltext keine XMLDoc hat; eine eigene Routine gleichen Namens zählt nicht.
      if FromLibrary then
      begin
        for Known in KnownRaises(Tokens[Index].Text) do
        begin
          AddClass(Known.ClassName, Known.UnitName);
        end;
      end;
    end;
  finally
    Lines.Free;
    Done.Free;
    Seen.Free;
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

function IndexOfText(const AName: string; const AList: TArray<string>): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AList) do
  begin
    if SameText(AList[Index], AName) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

class function TCompletionExceptions.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ASnippets: Boolean; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  Site: TExceptionSite;
  TryNames, TryUnits, Ancestors: TArray<string>;
  Units: TDictionary<string, TUnitIndex>;
  ByKey: TDictionary<string, Integer>;
  Entries: TList<TExceptionEntry>;
  Item, Fmt: TCompletionItem;
  Entry: TExceptionEntry;
  Symbol, ExceptionClass: TResolvedSymbol;
  DeclaringUnit: TUnitIndex;
  Existing, Index, Order, Rank: Integer;
  Sorted: TArray<TExceptionEntry>;
  Earlier: string;
  AnyTry: Boolean;
begin
  Result := AItems;
  if not SiteAt(ARequest.Tree.Tokens, AContext.ExceptionToken, Site) then
  begin
    Exit;
  end;
  TryNames := nil;
  TryUnits := nil;
  if Site.Kind = TExceptionSiteKind.Handler then
  begin
    TryNames := TryClasses(ARequest, Site, TryUnits);
  end;
  Units := TDictionary<string, TUnitIndex>.Create;
  ByKey := TDictionary<string, Integer>.Create;
  Entries := TList<TExceptionEntry>.Create;
  try
    Order := 0;
    for Item in AItems do
    begin
      if not TCompletionGenerics.ItemSymbol(ARequest, Units, Item, Symbol) or
        not ARequest.Resolver.ExceptionClassOf(Symbol, ExceptionClass) or
        (IndexOfText(Item.Name, Site.Handled) >= 0) then
      begin
        Continue;
      end;
      Entry := Default(TExceptionEntry);
      Entry.Item := Item;
      Entry.Key := UpperCase(ExceptionClass.UnitName + '.' + ExceptionClass.QualifiedName);
      if Length(Item.AdditionalEdits) = 0 then
      begin
        Entry.Preference := 0;
      end
      else if Symbol.SymbolKind = TIndexSymbolKind.TypeAlias then
      begin
        Entry.Preference := 1;
      end
      else
      begin
        Entry.Preference := 2;
      end;
      Entry.Library_ := ARequest.Resolver.DeclaringUnit(ExceptionClass, DeclaringUnit) and DeclaringUnit.Library_;
      Entry.TryRank := IndexOfText(Item.Name, TryNames);
      // Reihenfolge der Zweige: Ein früherer Zweig fängt schon alle Nachfahren seiner Klasse.
      Ancestors := ARequest.Resolver.AncestorNames(ExceptionClass);
      for Earlier in Site.Earlier do
      begin
        if IndexOfText(Earlier, Ancestors) > 0 then
        begin
          Entry.Item.Unreachable := Earlier;
          Break;
        end;
      end;
      Entry.Order := Order;
      Inc(Order);
      if ByKey.TryGetValue(Entry.Key, Existing) then
      begin
        if Entry.Preference < Entries[Existing].Preference then
        begin
          Entry.Order := Entries[Existing].Order;
          Entries[Existing] := Entry;
        end;
        Continue;
      end;
      ByKey.Add(Entry.Key, Entries.Count);
      Entries.Add(Entry);
    end;
    // Klassen aus dem try-Block, die die Liste (noch) nicht kennt, z. B. ohne Quellen der RTL im Index.
    for Rank := 0 to High(TryNames) do
    begin
      Existing := -1;
      for Index := 0 to Entries.Count - 1 do
      begin
        if SameText(Entries[Index].Item.Name, TryNames[Rank]) then
        begin
          Existing := Index;
        end;
      end;
      if (Existing >= 0) or (IndexOfText(TryNames[Rank], Site.Handled) >= 0) or
        (MatchScore(TryNames[Rank], AContext.Prefix, ARequest.Matching) = TFuzzyMatch.NoMatch) then
      begin
        Continue;
      end;
      Entry := Default(TExceptionEntry);
      Entry.Item.Name := TryNames[Rank];
      Entry.Item.Kind := KindClass;
      Entry.Item.Detail := TryUnits[Rank];
      Entry.Library_ := True;
      Entry.TryRank := Rank;
      Entry.Order := Order;
      Inc(Order);
      Entries.Add(Entry);
    end;
    // try-Block nach seiner Reihenfolge, dann Projekt vor Bibliothek, dann wie gesammelt; Order macht es eindeutig.
    Sorted := Entries.ToArray;
    TArray.Sort<TExceptionEntry>(Sorted, TComparer<TExceptionEntry>.Construct(
      function(const A, B: TExceptionEntry): Integer
      begin
        if (A.TryRank >= 0) <> (B.TryRank >= 0) then
        begin
          if A.TryRank >= 0 then
          begin
            Result := -1;
          end
          else
          begin
            Result := 1;
          end;
        end
        else if (A.TryRank >= 0) and (A.TryRank <> B.TryRank) then
        begin
          Result := A.TryRank - B.TryRank;
        end
        else if A.Library_ <> B.Library_ then
        begin
          if B.Library_ then
          begin
            Result := -1;
          end
          else
          begin
            Result := 1;
          end;
        end
        else
        begin
          Result := A.Order - B.Order;
        end;
      end));
    AnyTry := False;
    for Entry in Sorted do
    begin
      if Entry.TryRank >= 0 then
      begin
        AnyTry := True;
      end;
    end;
    Result := nil;
    for Entry in Sorted do
    begin
      Item := Entry.Item;
      if Site.Kind = TExceptionSiteKind.Raise_ then
      begin
        // raise EFoo.Create('|'), daneben EFoo.CreateFmt('|', []).
        Item.ExceptionGroup := GroupRaise;
        Item.FilterText := Item.Name;
        Fmt := Item;
        Item.Snippet := ASnippets;
        Fmt.Snippet := ASnippets;
        Fmt.Name := Item.Name + '.CreateFmt';
        Fmt.Kind := KindConstructor;
        if ASnippets then
        begin
          Item.InsertText := Item.Name + '.Create(''$0'')';
          Fmt.InsertText := Item.Name + '.CreateFmt(''$1'', [$2])$0';
        end
        else
        begin
          Item.InsertText := Item.Name + '.Create('''')';
          Fmt.InsertText := Item.Name + '.CreateFmt('''', [])';
        end;
        Result := Result + [Item, Fmt];
        Continue;
      end;
      // Gruppen „Aus dem try-Block“ und „Allgemein“ über den erwarteten Typ (#417).
      if AnyTry then
      begin
        Item.Expected := 'Exception';
        Item.Fits := Entry.TryRank >= 0;
        if Item.Fits then
        begin
          Item.ExceptionGroup := GroupTry;
        end
        else
        begin
          Item.ExceptionGroup := GroupGeneral;
        end;
      end;
      Result := Result + [Item];
    end;
  finally
    Entries.Free;
    ByKey.Free;
    Units.Free;
  end;
end;

end.
