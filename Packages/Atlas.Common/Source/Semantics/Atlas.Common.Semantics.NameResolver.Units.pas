unit Atlas.Common.Semantics.NameResolver.Units;

// Units der Namensauflösung: findet Units im Index (samt Namespaces des Projekts und Nachladen über die
// Suchpfade), merkt sich die Antworten, kennt die uses-Reihenfolge der aktuellen Unit und die Helfer-Typen
// jeder Unit.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place;

type
  TResolverUnits = class
  private type
    /// <summary>Positionen der Helfer-Typen eines Symbol-Arrays. Symbols hält das
    /// Array fest, damit der Zeigervergleich nie auf ein neu angelegtes Array an derselben Adresse trifft.</summary>
    TUnitHelpers = record
      Symbols: TArray<TIndexSymbol>;
      Positions: TArray<Integer>;
    end;
    /// <summary>Gefundene Unit an fester Adresse: Die Antworten halten nur den Verweis, statt bei jedem Treffer
    /// den ganzen TUnitIndex zu kopieren (laut Stichproben ein spürbarer Teil der Regelzeit).</summary>
    TUnitHolder = class
    private
      FValue: TUnitIndex;
    end;
    /// <summary>Gemerkte Antwort von FindUnit bzw. FindQualifierUnit (#1342); Holder nil, wenn nicht gefunden.
    /// </summary>
    TUnitAnswer = record
      Found: Boolean;
      Holder: TUnitHolder;
    end;
  private
    FPlace: TResolverPlace;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    // Units, die in diesem Resolver schon nicht gefunden wurden: nicht erneut suchen.
    FMissingUnits: TDictionary<string, Boolean>;
    // Antworten von FindUnit (Schlüssel Name groß) und FindQualifierUnit (Name, aktuelle Unit, Abschnitt): Jede
    // Typabfrage schlug sonst alle uses-Units samt Namespace-Varianten neu im Index nach (#1342).
    FUnitAnswers: TDictionary<string, TUnitAnswer>;
    FQualifierAnswers: TDictionary<string, TUnitAnswer>;
    // Besitzt alle Halter der Antworten; bleibt bis zum Ende des Resolvers, damit Verweise aus FindUnitRef auch
    // nach geleerten Antworten (SetNamespaces) gültig sind.
    FUnitHolders: TObjectList<TUnitHolder>;
    // Zeit im Nachladen (EnsureUnit) für das Diagnoselog (#647).
    FEnsureMs: Int64;
    // Letztes Ergebnis von ScopeUnits; gilt, solange die uses-Arrays dieselben sind.
    FScopeInterfaceUses: TArray<string>;
    FScopeImplementationUses: TArray<string>;
    FScopeUnitName: string;
    FScopeWithImplementation: Boolean;
    FScopeValid: Boolean;
    FScopeResult: TArray<string>;
    // Helfer-Positionen je Unit (Schlüssel Dateiname bzw. Unit-Name), einmal je Resolver ermittelt.
    FUnitHelpers: TDictionary<string, TUnitHelpers>;
    /// <summary>Gemerkte Antwort zu AName (FindUnit), bei Bedarf gesucht.</summary>
    function UnitAnswer(const AName: string): TUnitAnswer;
    /// <summary>Halter für AUnit, im Besitz des Resolvers.</summary>
    function HoldUnit(const AUnit: TUnitIndex): TUnitHolder;
    /// <summary>AName bzw. Namespace.AName im Index, ohne Nachladen.</summary>
    function SearchIndex(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Lädt AName über die Suchpfade nach und sucht dann im Index; misst die Zeit (#647).</summary>
    function EnsureAndSearch(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>FindUnit ohne gemerkte Antworten (außer der eigenen Unit).</summary>
    function SearchUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Steht AName (auch mit Namespace) in den uses der aktuellen Unit?</summary>
    function IsUsed(const AName: string): Boolean;
    /// <summary>FindQualifierUnit ohne gemerkte Antworten.</summary>
    function SearchQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(APlace: TResolverPlace; const AEnsureUnit: TEnsureUnitFunc);
    destructor Destroy; override;
    function FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Wie FindUnit, aber nur ein Verweis auf die gemerkte Unit (nie kopiert); gültig bis zum Ende des
    /// Resolvers. Für Schleifen über die uses-Units.</summary>
    function FindUnitRef(const AName: string; out AUnit: PUnitIndex): Boolean;
    /// <summary>Unit als Qualifizierer in einem Ausdruck (A.B.C): nachgeladen nur, wenn sie in uses steht.</summary>
    function FindQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Unit, in der AResolved deklariert ist.</summary>
    function UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    /// <summary>Units aus uses von AUnit, höchste Priorität zuerst (implementation, dann interface, jeweils von
    /// hinten), zuletzt System.</summary>
    function ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
    /// <summary>Positionen der Helfer-Typen (ohne Container) in AUnit.Symbols.</summary>
    function HelperPositions(const AUnit: TUnitIndex): TArray<Integer>;
    /// <summary>Ist AName der Anfang eines Unit-Namens im Bereich der aktuellen Unit?</summary>
    function IsUnitPrefix(const AName: string): Boolean;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace) für uses ohne Präfix.</summary>
    property Namespaces: TArray<string> read FNamespaces write SetNamespaces;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  Atlas.Common.Diagnostics.RequestScope;

constructor TResolverUnits.Create(APlace: TResolverPlace; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FPlace := APlace;
  FEnsureUnit := AEnsureUnit;
  FUnitHelpers := TDictionary<string, TUnitHelpers>.Create;
end;

destructor TResolverUnits.Destroy;
begin
  FQualifierAnswers.Free;
  FUnitAnswers.Free;
  FUnitHolders.Free;
  FMissingUnits.Free;
  FUnitHelpers.Free;
  inherited;
end;

procedure TResolverUnits.SetNamespaces(const AValue: TArray<string>);
var
  mIndex: Integer;
  mSame: Boolean;
begin
  // Ein gemeinsamer Resolver (TRuleDerived.Resolver) bekommt dieselben Namespaces von jeder Regel erneut: dann
  // die gemerkten Antworten behalten.
  mSame := Length(AValue) = Length(FNamespaces);
  mIndex := 0;
  while mSame and (mIndex <= High(AValue)) do
  begin
    mSame := SameText(AValue[mIndex], FNamespaces[mIndex]);
    Inc(mIndex);
  end;
  if mSame then
  begin
    Exit;
  end;
  FNamespaces := AValue;
  // Die gemerkten Antworten hängen an den Namespaces.
  if FUnitAnswers <> nil then
  begin
    FUnitAnswers.Clear;
  end;
  if FQualifierAnswers <> nil then
  begin
    FQualifierAnswers.Clear;
  end;
end;

function TResolverUnits.HoldUnit(const AUnit: TUnitIndex): TUnitHolder;
begin
  if FUnitHolders = nil then
  begin
    FUnitHolders := TObjectList<TUnitHolder>.Create(True);
  end;
  Result := TUnitHolder.Create;
  Result.FValue := AUnit;
  FUnitHolders.Add(Result);
end;

function TResolverUnits.UnitAnswer(const AName: string): TUnitAnswer;
var
  mKey: string;
  mUnit: TUnitIndex;
begin
  mKey := UpperCase(AName);
  if FUnitAnswers = nil then
  begin
    FUnitAnswers := TDictionary<string, TUnitAnswer>.Create;
  end
  else if FUnitAnswers.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result.Found := SearchUnit(AName, mUnit);
  Result.Holder := nil;
  if Result.Found then
  begin
    Result.Holder := HoldUnit(mUnit);
  end;
  FUnitAnswers.Add(mKey, Result);
end;

function TResolverUnits.FindUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mAnswer: TUnitAnswer;
begin
  // Die eigene Unit zuerst und nie gemerkt: Current wechselt mit PinTree.
  if SameText(AName, FPlace.Current.UnitName) then
  begin
    AUnit := FPlace.Current;
    Exit(True);
  end;
  // Ohne Index (Schnellbefehle in Tests) nur die eigene Unit.
  if FPlace.Index = nil then
  begin
    Exit(False);
  end;
  mAnswer := UnitAnswer(AName);
  Result := mAnswer.Found;
  if Result then
  begin
    AUnit := mAnswer.Holder.FValue;
  end
  else
  begin
    AUnit := Default(TUnitIndex);
  end;
end;

function TResolverUnits.FindUnitRef(const AName: string; out AUnit: PUnitIndex): Boolean;
var
  mAnswer: TUnitAnswer;
begin
  AUnit := nil;
  // Die eigene Unit als Momentaufnahme: Current kann sich während einer verschachtelten Abfrage ändern, der
  // Verweis darf das nicht.
  if SameText(AName, FPlace.Current.UnitName) then
  begin
    AUnit := @HoldUnit(FPlace.Current).FValue;
    Exit(True);
  end;
  if FPlace.Index = nil then
  begin
    Exit(False);
  end;
  mAnswer := UnitAnswer(AName);
  Result := mAnswer.Found;
  if Result then
  begin
    AUnit := @mAnswer.Holder.FValue;
  end;
end;

function TResolverUnits.SearchIndex(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mNamespace: string;
begin
  AUnit := Default(TUnitIndex);
  if FPlace.Index.FindUnit(AName, AUnit) then
  begin
    Exit(True);
  end;
  for mNamespace in FNamespaces do
  begin
    if FPlace.Index.FindUnit(mNamespace + '.' + AName, AUnit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverUnits.EnsureAndSearch(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  try
    // Der Unit-Resolver probiert die Namespaces selbst (SysUtils → System.SysUtils). Findet er AName
    // nicht, findet er auch Namespace.AName nicht; ein Suchlauf je Namespace kostete bei einer
    // fehlenden Unit ein Vielfaches (#647).
    Result := FEnsureUnit(AName) and SearchIndex(AName, AUnit);
  finally
    Inc(FEnsureMs, mWatch.ElapsedMilliseconds);
    TRequestDiagnostics.Note('ensureMs', Integer(FEnsureMs));
  end;
end;

function TResolverUnits.SearchUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
begin
  // Erst alle Schreibweisen im Index (uses SysUtils mit Namespace System → System.SysUtils), dann
  // erst nachladen: EnsureUnit durchsucht die Suchpfade aller Projekte und ist viel teurer (#647).
  mKey := UpperCase(AName);
  Result := SearchIndex(AName, AUnit);
  if Result or not Assigned(FEnsureUnit) or ((FMissingUnits <> nil) and FMissingUnits.ContainsKey(mKey)) then
  begin
    Exit;
  end;
  Result := EnsureAndSearch(AName, AUnit);
  if Result then
  begin
    Exit;
  end;
  // Diagnoselog (#647): Unit weder im Index noch über die Suchpfade gefunden; je Unit einmal.
  if FMissingUnits = nil then
  begin
    FMissingUnits := TDictionary<string, Boolean>.Create;
  end;
  FMissingUnits.Add(mKey, True);
  TRequestDiagnostics.Increment('missingUnits');
  TRequestDiagnostics.ResolveFailed('unitNotFound');
end;

function TResolverUnits.FindQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
  mAnswer: TUnitAnswer;
begin
  // Die eigene Unit nie gemerkt (wie in FindUnit); sonst hängt die Antwort an der aktuellen Unit und am Abschnitt
  // (uses von interface bzw. implementation).
  if SameText(AName, FPlace.Current.UnitName) then
  begin
    AUnit := FPlace.Current;
    Exit(True);
  end;
  mKey := UpperCase(AName) + '|' + FPlace.Current.FileName + '|' + FPlace.Current.UnitName + '|' +
    BoolToStr(FPlace.InImplementation);
  if FQualifierAnswers = nil then
  begin
    FQualifierAnswers := TDictionary<string, TUnitAnswer>.Create;
  end
  else if FQualifierAnswers.TryGetValue(mKey, mAnswer) then
  begin
    AUnit := Default(TUnitIndex);
    if mAnswer.Found then
    begin
      AUnit := mAnswer.Holder.FValue;
    end;
    Exit(mAnswer.Found);
  end;
  mAnswer.Found := SearchQualifierUnit(AName, AUnit);
  mAnswer.Holder := nil;
  if mAnswer.Found then
  begin
    mAnswer.Holder := HoldUnit(AUnit);
  end;
  FQualifierAnswers.Add(mKey, mAnswer);
  Result := mAnswer.Found;
end;

function TResolverUnits.IsUsed(const AName: string): Boolean;
var
  mUsed, mNamespace: string;
begin
  for mUsed in ScopeUnits(FPlace.Current, FPlace.InImplementation) do
  begin
    if SameText(mUsed, AName) then
    begin
      Exit(True);
    end;
    for mNamespace in FNamespaces do
    begin
      if SameText(mNamespace + '.' + mUsed, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TResolverUnits.SearchQualifierUnit(const AName: string; out AUnit: TUnitIndex): Boolean;
begin
  AUnit := Default(TUnitIndex);
  // Jeder Ausdruck wie Form1.Edit1.Text prüft, ob ein Präfix eine Unit ist. Nachladen durchsucht die
  // Suchpfade aller Projekte; das lohnt nur für Units aus uses, alle anderen nur aus dem Index (#647).
  if IsUsed(AName) then
  begin
    Exit(FindUnit(AName, AUnit));
  end;
  if SameText(AName, FPlace.Current.UnitName) then
  begin
    AUnit := FPlace.Current;
    Exit(True);
  end;
  // Ohne Index (Schnellbefehle in Tests) nur die eigene Unit.
  Result := (FPlace.Index <> nil) and SearchIndex(AName, AUnit);
end;

function TResolverUnits.UnitOf(const AResolved: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if (AResolved.Kind = TResolvedKind.Local) or FPlace.IsCurrentFile(AResolved.FileName) then
  begin
    AUnit := FPlace.Current;
    Exit(True);
  end;
  Result := (FPlace.Index <> nil) and (FPlace.Index.FindFile(AResolved.FileName, AUnit) or
    FindUnit(AResolved.UnitName, AUnit));
end;

function TResolverUnits.ScopeUnits(const AUnit: TUnitIndex; AWithImplementation: Boolean): TArray<string>;
var
  mIndex, mCount: Integer;
begin
  // Viele Aufrufe je Anfrage mit derselben Unit: Das Ergebnis hängt nur an den
  // uses-Arrays, dem Abschnitt und dem Unit-Namen. Die Felder halten die Arrays fest, daher trifft der
  // Zeigervergleich nie ein neu angelegtes Array an derselben Adresse.
  if FScopeValid and (Pointer(AUnit.InterfaceUses) = Pointer(FScopeInterfaceUses)) and
    (Pointer(AUnit.ImplementationUses) = Pointer(FScopeImplementationUses)) and
    (AWithImplementation = FScopeWithImplementation) and SameText(AUnit.UnitName, FScopeUnitName) then
  begin
    Exit(FScopeResult);
  end;
  // Höchste Priorität zuerst: letzte uses-Einträge gewinnen.
  SetLength(Result, Length(AUnit.ImplementationUses) + Length(AUnit.InterfaceUses) + 1);
  mCount := 0;
  if AWithImplementation then
  begin
    for mIndex := High(AUnit.ImplementationUses) downto 0 do
    begin
      Result[mCount] := AUnit.ImplementationUses[mIndex];
      Inc(mCount);
    end;
  end;
  for mIndex := High(AUnit.InterfaceUses) downto 0 do
  begin
    Result[mCount] := AUnit.InterfaceUses[mIndex];
    Inc(mCount);
  end;
  if not SameText(AUnit.UnitName, 'System') then
  begin
    Result[mCount] := 'System';
    Inc(mCount);
  end;
  SetLength(Result, mCount);
  FScopeInterfaceUses := AUnit.InterfaceUses;
  FScopeImplementationUses := AUnit.ImplementationUses;
  FScopeUnitName := AUnit.UnitName;
  FScopeWithImplementation := AWithImplementation;
  FScopeResult := Result;
  FScopeValid := True;
end;

function TResolverUnits.HelperPositions(const AUnit: TUnitIndex): TArray<Integer>;
var
  mKey: string;
  mEntry: TUnitHelpers;
  mPositions: TList<Integer>;
  mPosition: Integer;
begin
  mKey := UpperCase(AUnit.FileName + '|' + AUnit.UnitName);
  if FUnitHelpers.TryGetValue(mKey, mEntry) and (Pointer(mEntry.Symbols) = Pointer(AUnit.Symbols)) then
  begin
    Exit(mEntry.Positions);
  end;
  // Über den Index statt for-in: jede Kopie eines Symbol-Records kostet, und hier laufen alle
  // Symbole aller Units der uses-Liste durch (Diagnoselog 15.10.2026).
  mPositions := TList<Integer>.Create;
  try
    for mPosition := 0 to High(AUnit.Symbols) do
    begin
      if (AUnit.Symbols[mPosition].Kind = TIndexSymbolKind.HelperType) and (AUnit.Symbols[mPosition].Container = '') and
        (Length(AUnit.Symbols[mPosition].Ancestors) > 0) then
      begin
        mPositions.Add(mPosition);
      end;
    end;
    Result := mPositions.ToArray;
  finally
    mPositions.Free;
  end;
  mEntry.Symbols := AUnit.Symbols;
  mEntry.Positions := Result;
  FUnitHelpers.AddOrSetValue(mKey, mEntry);
end;

function TResolverUnits.IsUnitPrefix(const AName: string): Boolean;
var
  mUnitName, mNamespace: string;
begin
  if StartsText(AName + '.', FPlace.Current.UnitName) then
  begin
    Exit(True);
  end;
  for mUnitName in ScopeUnits(FPlace.Current, FPlace.InImplementation) do
  begin
    if StartsText(AName + '.', mUnitName) then
    begin
      Exit(True);
    end;
    for mNamespace in FNamespaces do
    begin
      if StartsText(AName + '.', mNamespace + '.' + mUnitName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

end.
