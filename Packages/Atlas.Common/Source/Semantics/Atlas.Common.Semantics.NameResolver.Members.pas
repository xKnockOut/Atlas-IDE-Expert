unit Atlas.Common.Semantics.NameResolver.Members;

// Mitglieder von Typen für die Namensauflösung: gleichnamige Mitglieder samt Vorfahren und Helfern, wie der
// Compiler sie sieht (Sichtbarkeit, Überladungen über Vorfahren hinweg, neu deklarierte Properties), dazu die
// Default-Property und Mitglieder ohne Rücksicht auf die Sichtbarkeit.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Typing;

type
  TResolverMembers = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FTyping: TResolverTyping;
    /// <summary>Mitglieder AName der Helfer von AType (samt Vorfahr-Helfern, #848); True, wenn einer welche hat.
    /// </summary>
    function HelperMembers(const AType: TResolvedSymbol; const AName: string;
      var AResult: TArray<TResolvedSymbol>): Boolean;
    /// <summary>Sichtbare Mitglieder AName des Helfers AHelper, mit den Bindungen ABindings.</summary>
    procedure AddHelperLevel(const AHelper: TResolvedSymbol; const ABindings: TArray<string>; const AName: string;
      var AResult: TArray<TResolvedSymbol>);
    /// <summary>Sichtbare Mitglieder AName, die AType selbst deklariert; AOverloads: nur noch Methoden.</summary>
    procedure AddLevelMembers(const AType: TResolvedSymbol; const AOwnerUnit: TUnitIndex; const AName: string;
      ALocalChain, AOverloads: Boolean; var AResult: TArray<TResolvedSymbol>);
  public
    constructor Create(APlace: TResolverPlace; AUnits: TResolverUnits; ATyping: TResolverTyping);
    /// <summary>Mitglieder AName von AType: die des nächsten Typs, der den Namen deklariert, bzw. seines Helfers.
    /// Sind dort alle Methoden mit overload oder override deklariert, kommen die Überladungen der Vorfahren dazu
    /// (#1326); eine neu deklarierte Property ohne Typ trägt Typ und Zugriffe der geerbten (MergedProperty).
    /// </summary>
    function FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    /// <summary>Erstes von FindMembers.</summary>
    function FindMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Neu deklarierte Property AOwn ohne Typ (property Items write SetItems;) mit Typ, Indexparametern
    /// und den Zugriffen der gleichnamigen Property der Vorfahren von AOwner, die AOwn nicht selbst nennt (#1326);
    /// AOwn unverändert, wenn die Vorfahren keine solche Property kennen.</summary>
    function MergedProperty(const AOwner, AOwn: TResolvedSymbol): TResolvedSymbol;
    /// <summary>Sichtbare Default-Property von AType oder seinen Vorfahren.</summary>
    function DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Mitglied AName von AType oder dem nächsten Vorfahren, der es deklariert, ohne Rücksicht auf die
    /// Sichtbarkeit (Doku-Vererbung, #654). Die Deklaration im Typ geht dem Rumpf vor.</summary>
    function DeclaredMember(const AType: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Deklaration der Property AName mit Typ in AType oder seinen Vorfahren (#491): "property Caption;"
    /// hebt nur die Sichtbarkeit an, Typ und Zugriff stehen weiter oben. ADepth wie bei MemberCandidates.
    /// </summary>
    function TypedProperty(const AType: TResolvedSymbol; const AName: string; out AProperty: TResolvedSymbol;
      out ADepth: Integer): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract;

/// <summary>Verdecken die Methoden AMembers ab AFrom die gleichnamigen der Vorfahren nicht? So ist es, wenn jede
/// overload trägt oder eine Methode überschreibt (override einer überladenen Methode bleibt überladen, Indy
/// TIdSMTP.Disconnect(Boolean) neben TIdTCPConnection.Disconnect, #1326). Felder und Properties verdecken immer.
/// </summary>
function KeepsAncestorOverloads(const AMembers: TArray<TResolvedSymbol>; AFrom: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := AFrom to High(AMembers) do
  begin
    if not (AMembers[mIndex].SymbolKind in cRoutineKinds) or
      ((IndexText('overload', AMembers[mIndex].Directives) < 0) and
      (IndexText('override', AMembers[mIndex].Directives) < 0)) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Wort hinter AKeyword (read, write) in der Signatur einer Property; '' ohne.</summary>
function PropertyAccessor(const ASignature, AKeyword: string): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if SameText(mWords[mIndex], AKeyword) then
    begin
      Exit(mWords[mIndex + 1]);
    end;
  end;
end;

/// <summary>Zugriff AKeyword (read, write) aus AOwn, sonst aus AInherited.</summary>
function MergedAccessor(const AOwn, AInherited, AKeyword: string): string;
begin
  Result := PropertyAccessor(AOwn, AKeyword);
  if Result = '' then
  begin
    Result := PropertyAccessor(AInherited, AKeyword);
  end;
end;

/// <summary>Signatur einer Property bis vor das erste read bzw. write ("property Items: TStrings").</summary>
function PropertyHead(const ASignature: string): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mWords := ASignature.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) do
  begin
    if MatchText(mWords[mIndex], ['read', 'write']) then
    begin
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mWords[mIndex];
  end;
end;

/// <summary>Steht AMember (aus AOwnerUnit) als Rumpf hinter der Deklaration des Typs AType? In einer anderen
/// Datei als der Typ (Include) entscheidet, ob AMember außerhalb des interface-Teils steht.</summary>
function IsBodyOf(const AOwnerUnit: TUnitIndex; const AMember: TIndexSymbol; const AType: TResolvedSymbol): Boolean;
var
  mEnd, mStart: TTextPosition;
begin
  if not SameText(AOwnerUnit.SymbolFile(AMember), AType.FileName) or
    ((AType.Range.EndPos.Line = 0) and (AType.Range.EndPos.Character = 0)) then
  begin
    Exit(not AMember.InInterface);
  end;
  mEnd := AType.Range.EndPos;
  mStart := AMember.Range.StartPos;
  Result := (mStart.Line > mEnd.Line) or ((mStart.Line = mEnd.Line) and (mStart.Character >= mEnd.Character));
end;

constructor TResolverMembers.Create(APlace: TResolverPlace; AUnits: TResolverUnits; ATyping: TResolverTyping);
begin
  inherited Create;
  FPlace := APlace;
  FUnits := AUnits;
  FTyping := ATyping;
end;

function TResolverMembers.MergedProperty(const AOwner, AOwn: TResolvedSymbol): TResolvedSymbol;
var
  mAncestor, mInherited: TResolvedSymbol;
  mCandidates: TArray<TResolvedSymbol>;
  mRead, mWrite: string;
begin
  Result := AOwn;
  if (AOwn.SymbolKind <> TIndexSymbolKind.Property_) or (AOwn.TypeName <> '') or
    not FTyping.AncestorOf(AOwner, mAncestor) then
  begin
    Exit;
  end;
  // Die Vorfahren können selbst nur neu deklarieren (property Items; im published-Teil): FindMembers führt sie
  // ebenso zusammen.
  mCandidates := FindMembers(mAncestor, AOwn.Name);
  if (Length(mCandidates) = 0) or (mCandidates[0].SymbolKind <> TIndexSymbolKind.Property_) or
    (mCandidates[0].TypeName = '') then
  begin
    Exit;
  end;
  mInherited := mCandidates[0];
  Result.TypeName := mInherited.TypeName;
  Result.TypeArgs := mInherited.TypeArgs;
  Result.MinArgs := mInherited.MinArgs;
  Result.MaxArgs := mInherited.MaxArgs;
  Result.ParamTypes := mInherited.ParamTypes;
  Result.IsDefault := AOwn.IsDefault or mInherited.IsDefault;
  mRead := MergedAccessor(AOwn.Signature, mInherited.Signature, 'read');
  mWrite := MergedAccessor(AOwn.Signature, mInherited.Signature, 'write');
  Result.Signature := PropertyHead(mInherited.Signature);
  if mRead <> '' then
  begin
    Result.Signature := Result.Signature + ' read ' + mRead;
  end;
  if mWrite <> '' then
  begin
    Result.Signature := Result.Signature + ' write ' + mWrite;
  end;
end;

procedure TResolverMembers.AddHelperLevel(const AHelper: TResolvedSymbol; const ABindings: TArray<string>;
  const AName: string; var AResult: TArray<TResolvedSymbol>);
var
  mHelperUnit: TUnitIndex;
  mPosition: Integer;
  mFound: TResolvedSymbol;
begin
  if not FUnits.UnitOf(AHelper, mHelperUnit) then
  begin
    Exit;
  end;
  for mPosition in mHelperUnit.SymbolsNamed(AName) do
  begin
    if SameText(mHelperUnit.Symbols[mPosition].Container, AHelper.QualifiedName) and
      FTyping.IsVisible(mHelperUnit.Symbols[mPosition], mHelperUnit, AHelper, False) then
    begin
      mFound := TResolvedSymbol.FromIndex(mHelperUnit, mHelperUnit.Symbols[mPosition]);
      mFound.Bindings := ABindings;
      TResolvedSymbol.AddDistinct(AResult, mFound);
    end;
  end;
end;

function TResolverMembers.HelperMembers(const AType: TResolvedSymbol; const AName: string;
  var AResult: TArray<TResolvedSymbol>): Boolean;
var
  mHelper, mParent: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := False;
  if not FTyping.HelperFor(AType, mHelper) then
  begin
    Exit;
  end;
  for mDepth := 0 to cMaxDepth do
  begin
    AddHelperLevel(mHelper, AType.Bindings, AName, AResult);
    if AResult <> nil then
    begin
      Exit(True);
    end;
    if not FTyping.HelperParent(mHelper, mParent) then
    begin
      Exit;
    end;
    mHelper := mParent;
  end;
end;

procedure TResolverMembers.AddLevelMembers(const AType: TResolvedSymbol; const AOwnerUnit: TUnitIndex;
  const AName: string; ALocalChain, AOverloads: Boolean; var AResult: TArray<TResolvedSymbol>);
var
  mPosition: Integer;
  mHidden: Boolean;
  mFound: TResolvedSymbol;
  mTypeName: string;
begin
  mTypeName := AType.QualifiedName;
  mHidden := False;
  // Erste Fundstelle: die Deklaration im Typ steht vor dem Rumpf in implementation.
  for mPosition in AOwnerUnit.SymbolsNamed(AName) do
  begin
    if not SameText(AOwnerUnit.Symbols[mPosition].Container, mTypeName) or
      (AOverloads and not (AOwnerUnit.Symbols[mPosition].Kind in cRoutineKinds)) then
    begin
      Continue;
    end;
    // Ist die Deklaration unsichtbar, gilt das auch für ihren Rumpf (implementation, dort public). Weitere
    // Deklarationen im Typ prüft IsVisible einzeln: Überladungen dürfen anders sichtbar sein
    // (System.TMonitor.Enter: strict private als Instanzmethode, public als Klassenmethode). Rumpf heißt
    // hinter dem Typ; InInterface allein trennt das nicht bei Typen im implementation-Teil (Skia4Delphi,
    // #1328).
    if mHidden and IsBodyOf(AOwnerUnit, AOwnerUnit.Symbols[mPosition], AType) then
    begin
      Continue;
    end;
    if not FTyping.IsVisible(AOwnerUnit.Symbols[mPosition], AOwnerUnit, AType, ALocalChain) then
    begin
      mHidden := True;
      Continue;
    end;
    mFound := TResolvedSymbol.FromIndex(AOwnerUnit, AOwnerUnit.Symbols[mPosition]);
    mFound.Bindings := AType.Bindings;
    if mFound.SymbolKind = TIndexSymbolKind.Property_ then
    begin
      mFound := MergedProperty(AType, mFound);
    end;
    TResolvedSymbol.AddDistinct(AResult, mFound);
  end;
end;

function TResolverMembers.FindMembers(const AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mDepth, mLevelStart: Integer;
  mLocalChain, mOverloads: Boolean;
begin
  Result := nil;
  mCurrent := AType;
  mLocalChain := False;
  // Nach einer Stufe, deren Methoden alle overload bzw. override tragen: nur noch Methoden der Vorfahren sammeln.
  mOverloads := False;
  for mDepth := 0 to cMaxDepth do
  begin
    // Helfer zuerst: ihre Mitglieder verdecken gleichnamige des Typs; danach die Vorfahr-Helfer (#848).
    if (not mOverloads and HelperMembers(mCurrent, AName, Result)) or mCurrent.Builtin or
      not FUnits.UnitOf(mCurrent, mOwnerUnit) then
    begin
      Exit;
    end;
    mLocalChain := mLocalChain or FPlace.IsCurrentFile(mOwnerUnit.FileName);
    mLevelStart := Length(Result);
    AddLevelMembers(mCurrent, mOwnerUnit, AName, mLocalChain, mOverloads, Result);
    // Eine Stufe ohne neue Methode (nur Rümpfe, nur Gleiches) ändert nichts an der Überladung.
    if Length(Result) > mLevelStart then
    begin
      if not KeepsAncestorOverloads(Result, mLevelStart) then
      begin
        Exit;
      end;
      mOverloads := True;
    end;
    if not FTyping.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit;
    end;
    mCurrent := mAncestor;
  end;
end;

function TResolverMembers.FindMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mMembers: TArray<TResolvedSymbol>;
begin
  mMembers := FindMembers(AType, AName);
  Result := Length(mMembers) > 0;
  if Result then
  begin
    AResult := mMembers[0];
  end;
end;

function TResolverMembers.DefaultProperty(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mIndex, mDepth: Integer;
begin
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if mCurrent.Builtin or not FUnits.UnitOf(mCurrent, mOwnerUnit) then
    begin
      Exit(False);
    end;
    // Über den Index: for-in kopierte bei jedem X[i] jedes Symbol der Unit (System.Classes: Tausende).
    for mIndex := 0 to High(mOwnerUnit.Symbols) do
    begin
      if mOwnerUnit.Symbols[mIndex].IsDefault and (mOwnerUnit.Symbols[mIndex].Kind = TIndexSymbolKind.Property_) and
        SameText(mOwnerUnit.Symbols[mIndex].Container, mCurrent.QualifiedName) and
        FTyping.IsVisible(mOwnerUnit.Symbols[mIndex], mOwnerUnit, mCurrent, False) then
      begin
        AResult := TResolvedSymbol.FromIndex(mOwnerUnit, mOwnerUnit.Symbols[mIndex]);
        AResult.Bindings := mCurrent.Bindings;
        Exit(True);
      end;
    end;
    if not FTyping.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit(False);
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

function TResolverMembers.DeclaredMember(const AType: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mPosition, mDepth: Integer;
begin
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if mCurrent.Builtin or not FUnits.UnitOf(mCurrent, mOwnerUnit) then
    begin
      Exit(False);
    end;
    // Über die Namenstabelle statt aller Symbole je Vorfahrstufe (Code-Review P-05).
    for mPosition in mOwnerUnit.SymbolsNamed(AName) do
    begin
      if SameText(mOwnerUnit.Symbols[mPosition].Container, mCurrent.QualifiedName) then
      begin
        AResult := TResolvedSymbol.FromIndex(mOwnerUnit, mOwnerUnit.Symbols[mPosition]);
        Exit(True);
      end;
    end;
    if not FTyping.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit(False);
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

function TResolverMembers.TypedProperty(const AType: TResolvedSymbol; const AName: string;
  out AProperty: TResolvedSymbol; out ADepth: Integer): Boolean;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mOwnerUnit: TUnitIndex;
  mPosition, mDepth: Integer;
  mTypeName: string;
begin
  AProperty := TResolvedSymbol.Empty;
  ADepth := 0;
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if mCurrent.Builtin or not FUnits.UnitOf(mCurrent, mOwnerUnit) then
    begin
      Exit(False);
    end;
    mTypeName := mCurrent.QualifiedName;
    for mPosition := 0 to High(mOwnerUnit.Symbols) do
    begin
      if (mOwnerUnit.Symbols[mPosition].Kind = TIndexSymbolKind.Property_) and
        (mOwnerUnit.Symbols[mPosition].TypeName <> '') and
        SameText(mOwnerUnit.Symbols[mPosition].Container, mTypeName) and
        SameText(mOwnerUnit.Symbols[mPosition].Name, AName) then
      begin
        AProperty := TResolvedSymbol.FromIndex(mOwnerUnit, mOwnerUnit.Symbols[mPosition]);
        ADepth := mDepth;
        Exit(True);
      end;
    end;
    if not FTyping.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit(False);
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

end.
