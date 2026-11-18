unit Atlas.Common.Mcp.ImplementationTools;

// MCP-Werkzeug find_implementations (#2635): welche Klassen eine Interface- oder virtuelle Methode umsetzen,
// wo die Rümpfe stehen und wie (umgesetzt, überschrieben, abstrakt, reintroduce, Zuordnung, Delegation). Die
// Stellen kommen aus TImplementationSites, wie bei „Gehe zu Implementierung“ und der Zahl in
// get_call_hierarchy. Bei Klassen und Interfaces statt Methoden die Nachfahren bzw. umsetzenden Klassen.
// Ein mehrdeutiger Name ergibt die Trefferliste, ein unbekannter einen Hinweis.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.ImplementationSites;

type
  TMcpImplementationTools = class
  public const
    /// <summary>Höchstens so viele Zeilen je Rumpf mit includeBody.</summary>
    cMaxBodyLines = 20;
    /// <summary>Höchstens so viele Treffer in der Liste eines mehrdeutigen Namens.</summary>
    cMaxCandidates = 20;
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FImpactOptionsFor: TImpactOptionsProvider;
    function Candidates(const AName: string): TArray<TSymbolLocation>;
    function IsTest(const ASite: TImplementationSite): Boolean;
    function BodyText(const AFileName: string; AStartLine, AEndLine: Integer; out ATruncated: Boolean): string;
    function TypeSites(const ALocation: TSymbolLocation): TArray<TImplementationSite>;
    function MethodSites(const ALocation: TSymbolLocation; out AInterface: Boolean): TArray<TImplementationSite>;
    function Markdown(const ATitle: string; const ASites: TArray<TImplementationSite>;
      AIncludeBody: Boolean): string;
    function Json(const ALocation: TSymbolLocation; const AKind: string; const ASites: TArray<TImplementationSite>;
      AIncludeBody: Boolean): string;
    function Ambiguous(const AName: string; const AFound: TArray<TSymbolLocation>; AJson: Boolean): string;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText);
    /// <summary>find_implementations für den Namen AName (TFoo.Bar, IFoo.Bar, TFoo oder Unit.TFoo.Bar).
    /// AJson: Antwort als JSON statt Markdown.</summary>
    function Find(const AName: string; AIncludeBody, AJson: Boolean): string;
    /// <summary>Text der Art für die Markdown-Antwort (umgesetzt, überschrieben …).</summary>
    class function KindText(AKind: TImplementationKind): string; static;
    /// <summary>Testunits wie bei get_impact (testUnits.pattern, Units des Testprogramms); nicht gesetzt: keine
    /// Kennzeichnung.</summary>
    property ImpactOptionsFor: TImpactOptionsProvider read FImpactOptionsFor write FImpactOptionsFor;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Lines;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TImplementationToolsText = (NoSymbol, NotAMethod, Ambiguous, AmbiguousHint, Header, HeaderOne, HeaderType, NoneFound,
    Test, Shortened, KindOwn, KindImplements, KindOverrides, KindAbstract, KindReintroduces, KindHides, KindMapped,
    KindInherited, KindDelegated, KindDelegatedToField, NotDispatched);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TImplementationToolsText] of TAtlasText = (
    (De: 'Kein Symbol "%s" im Index.'; En: 'No symbol "%s" in the index.'),
    (De: '%s ist weder eine Methode noch ein Typ.'; En: '%s is neither a method nor a type.'),
    (De: '"%s" ist mehrdeutig, %d Treffer:'; En: '"%s" is ambiguous, %d matches:'),
    (De: 'Mit Unit.TTyp.Name genauer fassen.'; En: 'Narrow it down with Unit.TType.Name.'),
    (De: '%d Umsetzungen von %s'; En: '%d implementations of %s'),
    (De: '1 Umsetzung von %s'; En: '1 implementation of %s'),
    (De: '%d Nachfahren bzw. umsetzende Klassen von %s'; En: '%d descendants or implementing classes of %s'),
    (De: '  (keine)'; En: '  (none)'),
    (De: 'Test'; En: 'test'),
    (De: '… gekürzt, %d von %d Zeilen'; En: '… shortened, %d of %d lines'),
    (De: 'eigener Rumpf'; En: 'own body'),
    (De: 'umgesetzt'; En: 'implemented'),
    (De: 'überschrieben'; En: 'overridden'),
    (De: 'abstrakt'; En: 'abstract'),
    (De: 'reintroduce'; En: 'reintroduce'),
    (De: 'verdeckt (ohne override)'; En: 'hides (without override)'),
    (De: 'Zuordnung %s'; En: 'mapping %s'),
    (De: 'geerbt aus %s'; En: 'inherited from %s'),
    (De: 'delegiert über %s an %s'; En: 'delegated via %s to %s'),
    (De: 'delegiert an Feld %s (Umsetzung erst zur Laufzeit bekannt)';
     En: 'delegated to field %s (implementation known only at run time)'),
    (De: 'Hinweis: %s ist weder virtuell noch Methode eines Interfaces; der Aufruf erreicht nur diesen Rumpf.';
     En: 'Note: %s is neither virtual nor a method of an interface; a call reaches only this body.'));

  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType];

{ TMcpImplementationTools }

constructor TMcpImplementationTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
end;

class function TMcpImplementationTools.KindText(AKind: TImplementationKind): string;
begin
  case AKind of
    TImplementationKind.Own:
      Result := cTexts[TImplementationToolsText.KindOwn].Text;
    TImplementationKind.Implements:
      Result := cTexts[TImplementationToolsText.KindImplements].Text;
    TImplementationKind.Overrides:
      Result := cTexts[TImplementationToolsText.KindOverrides].Text;
    TImplementationKind.Abstract_:
      Result := cTexts[TImplementationToolsText.KindAbstract].Text;
    TImplementationKind.Reintroduces:
      Result := cTexts[TImplementationToolsText.KindReintroduces].Text;
    TImplementationKind.Hides:
      Result := cTexts[TImplementationToolsText.KindHides].Text;
  else
    Result := '';
  end;
end;

/// <summary>Art mit Einzelheiten: Zuordnung mit dem Methodennamen, Delegation mit Property und Klasse.</summary>
function SiteKindText(const ASite: TImplementationSite): string;
begin
  case ASite.Kind of
    TImplementationKind.Mapped:
      Result := cTexts[TImplementationToolsText.KindMapped].Fmt([ASite.MethodName]);
    TImplementationKind.Inherited_:
      Result := cTexts[TImplementationToolsText.KindInherited].Fmt([ASite.DeclaringType]);
    TImplementationKind.Delegated:
      Result := cTexts[TImplementationToolsText.KindDelegated].Fmt([ASite.Via, ASite.DeclaringType]);
    TImplementationKind.DelegatedToField:
      Result := cTexts[TImplementationToolsText.KindDelegatedToField].Fmt([ASite.Via]);
  else
    Result := TMcpImplementationTools.KindText(ASite.Kind);
  end;
end;

/// <summary>Schlüssel eines Symbols für die Mehrdeutigkeit: Deklaration und Rumpf einer Methode sind eins.
/// </summary>
function SymbolKey(const ALocation: TSymbolLocation): string;
begin
  Result := UpperCase(ALocation.UnitName + '|' + ALocation.Symbol.QualifiedName);
end;

function TMcpImplementationTools.Candidates(const AName: string): TArray<TSymbolLocation>;
var
  mLookup: TMcpIndexTools;
  mMatches: TArray<TSymbolLocation>;
  mSeen: TDictionary<string, Boolean>;
  mLocation: TSymbolLocation;
begin
  Result := nil;
  mLookup := TMcpIndexTools.Create(FIndex, nil);
  try
    mMatches := mLookup.Matches(AName);
  finally
    mLookup.Free;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mLocation in mMatches do
    begin
      if not ((mLocation.Symbol.Kind in cRoutineKinds) or (mLocation.Symbol.Kind in cTypeKinds)) or
        mSeen.ContainsKey(SymbolKey(mLocation)) then
      begin
        Continue;
      end;
      mSeen.Add(SymbolKey(mLocation), True);
      Result := Result + [mLocation];
    end;
  finally
    mSeen.Free;
  end;
end;

function TMcpImplementationTools.IsTest(const ASite: TImplementationSite): Boolean;
var
  mOptions: TImpactOptions;
begin
  Result := False;
  if Assigned(FImpactOptionsFor) then
  begin
    mOptions := FImpactOptionsFor(TDocumentUris.FromPath(ASite.FileName));
    Result := mOptions.Tests.Contains(ASite.UnitName);
  end;
end;

function TMcpImplementationTools.BodyText(const AFileName: string; AStartLine, AEndLine: Integer;
  out ATruncated: Boolean): string;
var
  mText: string;
  mLines: TArray<string>;
  mLast, mLine: Integer;
begin
  Result := '';
  ATruncated := False;
  if not (Assigned(FReadText) and FReadText(AFileName, mText)) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(mText);
  mLast := AEndLine;
  if mLast > High(mLines) then
  begin
    mLast := High(mLines);
  end;
  if mLast - AStartLine + 1 > cMaxBodyLines then
  begin
    mLast := AStartLine + cMaxBodyLines - 1;
    ATruncated := True;
  end;
  for mLine := AStartLine to mLast do
  begin
    Result := Result + mLines[mLine] + #10;
  end;
  if ATruncated then
  begin
    Result := Result + cTexts[TImplementationToolsText.Shortened].Fmt([cMaxBodyLines, AEndLine - AStartLine + 1]) +
      #10;
  end;
end;

function TMcpImplementationTools.TypeSites(const ALocation: TSymbolLocation): TArray<TImplementationSite>;
var
  mDescendant: TSymbolLocation;
  mSite: TImplementationSite;
begin
  Result := nil;
  for mDescendant in TLspImplementations.AllDescendantsOf(FIndex, ALocation.Symbol.QualifiedName) do
  begin
    mSite := Default(TImplementationSite);
    mSite.TypeName := mDescendant.Symbol.QualifiedName;
    mSite.DeclaringType := mSite.TypeName;
    mSite.Kind := TImplementationKind.Implements;
    if ALocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType then
    begin
      mSite.Kind := TImplementationKind.Overrides;
    end;
    mSite.UnitName := mDescendant.UnitName;
    mSite.FileName := mDescendant.FileName;
    mSite.Range := mDescendant.Symbol.Range;
    mSite.SelectionRange := mDescendant.Symbol.SelectionRange;
    Result := Result + [mSite];
  end;
end;

function TMcpImplementationTools.MethodSites(const ALocation: TSymbolLocation;
  out AInterface: Boolean): TArray<TImplementationSite>;
begin
  AInterface := TLspImplementations.IsInterfaceType(FIndex, ALocation.Symbol.Container);
  Result := TImplementationSites.Find(FIndex, nil, ALocation.Symbol.Container, ALocation.Symbol.Name,
    ALocation.FileName, AInterface);
end;

function TMcpImplementationTools.Markdown(const ATitle: string; const ASites: TArray<TImplementationSite>;
  AIncludeBody: Boolean): string;
var
  mLines: TStringList;
  mSite: TImplementationSite;
  mLine, mBody: string;
  mTruncated: Boolean;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(ATitle);
    if Length(ASites) = 0 then
    begin
      mLines.Add(cTexts[TImplementationToolsText.NoneFound].Text);
    end;
    for mSite in ASites do
    begin
      if mSite.MethodName = '' then
      begin
        mLine := Format('  %s  %s:%d', [mSite.TypeName, mSite.FileName, mSite.SelectionRange.StartPos.Line + 1]);
      end
      else
      begin
        mLine := Format('  %s.%s  %s:%d  «%s»', [mSite.TypeName, mSite.MethodName, mSite.FileName,
          mSite.SelectionRange.StartPos.Line + 1, SiteKindText(mSite)]);
      end;
      if IsTest(mSite) then
      begin
        mLine := mLine + '  (' + cTexts[TImplementationToolsText.Test].Text + ')';
      end;
      mLines.Add(mLine);
      if AIncludeBody and (mSite.MethodName <> '') then
      begin
        mBody := BodyText(mSite.FileName, mSite.Range.StartPos.Line, mSite.Range.EndPos.Line, mTruncated);
        if mBody <> '' then
        begin
          mLines.Add('```pascal');
          mLines.Add(TrimRight(mBody));
          mLines.Add('```');
        end;
      end;
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

function SiteJson(const ASite: TImplementationSite; ATest: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', ASite.TypeName);
  if ASite.MethodName <> '' then
  begin
    Result.AddPair('method', ASite.MethodName);
    Result.AddPair('declaringType', ASite.DeclaringType);
  end;
  Result.AddPair('kind', TImplementationSites.KindName(ASite.Kind));
  if ASite.Via <> '' then
  begin
    Result.AddPair('via', ASite.Via);
  end;
  Result.AddPair('unit', ASite.UnitName);
  Result.AddPair('file', ASite.FileName);
  Result.AddPair('line', TJSONNumber.Create(ASite.SelectionRange.StartPos.Line + 1));
  Result.AddPair('hasBody', TJSONBool.Create(ASite.HasBody));
  Result.AddPair('test', TJSONBool.Create(ATest));
end;

function TMcpImplementationTools.Json(const ALocation: TSymbolLocation; const AKind: string;
  const ASites: TArray<TImplementationSite>; AIncludeBody: Boolean): string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mSite: TImplementationSite;
  mBody: string;
  mTruncated: Boolean;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', 'json');
    mRoot.AddPair('symbol', ALocation.Symbol.QualifiedName);
    mRoot.AddPair('unit', ALocation.UnitName);
    mRoot.AddPair('kind', AKind);
    mRoot.AddPair('count', TJSONNumber.Create(Length(ASites)));
    mList := TJSONArray.Create;
    mRoot.AddPair('implementations', mList);
    for mSite in ASites do
    begin
      mItem := SiteJson(mSite, IsTest(mSite));
      mList.AddElement(mItem);
      if AIncludeBody and (mSite.MethodName <> '') then
      begin
        mBody := BodyText(mSite.FileName, mSite.Range.StartPos.Line, mSite.Range.EndPos.Line, mTruncated);
        mItem.AddPair('body', mBody);
        mItem.AddPair('bodyTruncated', TJSONBool.Create(mTruncated));
      end;
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function TMcpImplementationTools.Ambiguous(const AName: string; const AFound: TArray<TSymbolLocation>;
  AJson: Boolean): string;
var
  mLines: TStringList;
  mIndex: Integer;
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
begin
  if AJson then
  begin
    mRoot := TJSONObject.Create;
    try
      mRoot.AddPair('format', 'json');
      mRoot.AddPair('ambiguous', AName);
      mList := TJSONArray.Create;
      mRoot.AddPair('candidates', mList);
      for mIndex := 0 to High(AFound) do
      begin
        mItem := TJSONObject.Create;
        mItem.AddPair('symbol', AFound[mIndex].UnitName + '.' + AFound[mIndex].Symbol.QualifiedName);
        mItem.AddPair('file', AFound[mIndex].FileName);
        mItem.AddPair('line', TJSONNumber.Create(AFound[mIndex].Symbol.SelectionRange.StartPos.Line + 1));
        mList.AddElement(mItem);
      end;
      Result := mRoot.ToJSON([]);
    finally
      mRoot.Free;
    end;
    Exit;
  end;
  mLines := TStringList.Create;
  try
    mLines.Add(cTexts[TImplementationToolsText.Ambiguous].Fmt([AName, Length(AFound)]));
    for mIndex := 0 to High(AFound) do
    begin
      if mIndex >= cMaxCandidates then
      begin
        Break;
      end;
      mLines.Add(Format('  %s.%s  %s:%d', [AFound[mIndex].UnitName, AFound[mIndex].Symbol.QualifiedName,
        AFound[mIndex].FileName, AFound[mIndex].Symbol.SelectionRange.StartPos.Line + 1]));
    end;
    mLines.Add(cTexts[TImplementationToolsText.AmbiguousHint].Text);
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

function TMcpImplementationTools.Find(const AName: string; AIncludeBody, AJson: Boolean): string;
var
  mFound: TArray<TSymbolLocation>;
  mLocation: TSymbolLocation;
  mSites: TArray<TImplementationSite>;
  mInterface: Boolean;
  mKind, mTitle: string;
begin
  mFound := Candidates(AName);
  if Length(mFound) = 0 then
  begin
    Exit(cTexts[TImplementationToolsText.NoSymbol].Fmt([AName]));
  end;
  if Length(mFound) > 1 then
  begin
    Exit(Ambiguous(AName, mFound, AJson));
  end;
  mLocation := mFound[0];
  if mLocation.Symbol.Kind in cTypeKinds then
  begin
    mSites := TypeSites(mLocation);
    mKind := 'type';
    mTitle := cTexts[TImplementationToolsText.HeaderType].Fmt([Length(mSites), mLocation.Symbol.QualifiedName]);
  end
  else if mLocation.Symbol.Container = '' then
  begin
    Exit(cTexts[TImplementationToolsText.NotAMethod].Fmt([mLocation.Symbol.QualifiedName]));
  end
  else
  begin
    mSites := MethodSites(mLocation, mInterface);
    mKind := 'virtual';
    if mInterface then
    begin
      mKind := 'interface';
    end;
    if Length(mSites) = 1 then
    begin
      mTitle := cTexts[TImplementationToolsText.HeaderOne].Fmt([mLocation.Symbol.QualifiedName]);
    end
    else
    begin
      mTitle := cTexts[TImplementationToolsText.Header].Fmt([Length(mSites), mLocation.Symbol.QualifiedName]);
    end;
    if not mInterface and not mLocation.Symbol.IsVirtual then
    begin
      mKind := 'static';
      mTitle := mTitle + #10 + cTexts[TImplementationToolsText.NotDispatched].Fmt([mLocation.Symbol.QualifiedName]);
    end;
  end;
  if AJson then
  begin
    Result := Json(mLocation, mKind, mSites, AIncludeBody);
  end
  else
  begin
    Result := Markdown(mTitle, mSites, AIncludeBody);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.ImplementationTools', cTexts);

end.
