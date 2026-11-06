unit Atlas.Common.Semantics.NameResolver.Lookup;

// Nachschlagen von Namen auf Unit-Ebene: in einer Unit, in der Unit samt ihren uses und als Typtext mit
// Typargumenten (TList<TKunde>), so wie der Compiler die erste Fundstelle wählt.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units;

type
  TResolverLookup = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
  public
    constructor Create(APlace: TResolverPlace; AUnits: TResolverUnits);
    /// <summary>Name AName auf Unit-Ebene in AUnit. AArity: -1 beliebig, 0 ohne Typargumente (nicht generische
    /// Typen zuerst), sonst Zahl der Typparameter, cNonGenericArity nur Typen ohne Typparameter.</summary>
    function LookupInUnit(const AUnit: TUnitIndex; const AName: string; AOnlyInterface, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer): Boolean; overload;
    /// <summary>Wie oben mit AArity = -1.</summary>
    function LookupInUnit(const AUnit: TUnitIndex; const AName: string; AOnlyInterface, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol): Boolean; overload;
    /// <summary>Name AName, wie er in AUnit stünde: erst die Unit selbst, dann ihre uses.</summary>
    function LookupGlobal(const AUnit: TUnitIndex; const AName: string; AWithImplementation, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol; AArity: Integer): Boolean; overload;
    /// <summary>Wie oben mit AArity = -1.</summary>
    function LookupGlobal(const AUnit: TUnitIndex; const AName: string; AWithImplementation, AOnlyTypes: Boolean;
      out AResult: TResolvedSymbol): Boolean; overload;
    /// <summary>Typname (auch Unit.Typ), wie er in AFromUnit stünde.</summary>
    function ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
      AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean; overload;
    /// <summary>Wie oben mit AArity = -1.</summary>
    function ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
      AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean; overload;
    /// <summary>Typtext mit Typargumenten (TList&lt;TKunde&gt;): generischer Typ mit passender Stelligkeit,
    /// Argumente gebunden; eingebaute Typen ohne Deklaration mit Builtin.</summary>
    function ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Typtext mit Unit-Präfixen, wie er in AFromUnit gemeint ist (auch in Typargumenten).</summary>
    function QualifyType(const AText: string; const AFromUnit: TUnitIndex; AWithImplementation: Boolean): string;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Kommt ASymbol für LookupInUnit im Durchgang APass in Frage?</summary>
function Accepts(const ASymbol: TIndexSymbol; AOnlyInterface, AOnlyTypes: Boolean; AArity, APass: Integer): Boolean;
begin
  if (AOnlyInterface and not ASymbol.InInterface) or (AOnlyTypes and not (ASymbol.Kind in cTypeKinds)) then
  begin
    Result := False;
  end
  // Unit-Ebene; Enum-Werte sind ohne SCOPEDENUMS auch dort sichtbar (#849).
  else if (ASymbol.Container <> '') and ((ASymbol.Kind <> TIndexSymbolKind.EnumMember) or ASymbol.ScopedEnum) then
  begin
    Result := False;
  end
  else if not AOnlyTypes then
  begin
    Result := True;
  end
  else if AArity > 0 then
  begin
    Result := Length(TResolverText.SplitArgs(ASymbol.TypeParams)) = AArity;
  end
  else
  begin
    Result := not (((AArity = 0) and (APass = 0)) or (AArity = cNonGenericArity)) or (ASymbol.TypeParams = '');
  end;
end;

constructor TResolverLookup.Create(APlace: TResolverPlace; AUnits: TResolverUnits);
begin
  inherited Create;
  FPlace := APlace;
  FUnits := AUnits;
end;

function TResolverLookup.LookupInUnit(const AUnit: TUnitIndex; const AName: string;
  AOnlyInterface, AOnlyTypes: Boolean; out AResult: TResolvedSymbol): Boolean;
begin
  Result := LookupInUnit(AUnit, AName, AOnlyInterface, AOnlyTypes, AResult, -1);
end;

function TResolverLookup.LookupGlobal(const AUnit: TUnitIndex; const AName: string;
  AWithImplementation, AOnlyTypes: Boolean; out AResult: TResolvedSymbol): Boolean;
begin
  Result := LookupGlobal(AUnit, AName, AWithImplementation, AOnlyTypes, AResult, -1);
end;

function TResolverLookup.ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
begin
  Result := ResolveTypeName(ATypeName, AFromUnit, AWithImplementation, AResult, -1);
end;

function TResolverLookup.LookupInUnit(const AUnit: TUnitIndex; const AName: string;
  AOnlyInterface, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  mPass, mPosition: Integer;
  mPositions: TArray<Integer>;
begin
  // Über die Namenstabelle statt linear durch alle Symbole (Diagnoselog 15.10.2026).
  mPositions := AUnit.SymbolsNamed(AName);
  // Mit Typargumenten nur generische Typen passender Stelligkeit; ohne zuerst nicht generische.
  for mPass := 0 to 1 do
  begin
    for mPosition in mPositions do
    begin
      if Accepts(AUnit.Symbols[mPosition], AOnlyInterface, AOnlyTypes, AArity, mPass) then
      begin
        AResult := TResolvedSymbol.FromIndex(AUnit, AUnit.Symbols[mPosition]);
        Exit(True);
      end;
    end;
    if not (AOnlyTypes and (AArity = 0)) then
    begin
      Break;
    end;
  end;
  Result := False;
end;

function TResolverLookup.LookupGlobal(const AUnit: TUnitIndex; const AName: string;
  AWithImplementation, AOnlyTypes: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  mUnitName: string;
  mUsed: PUnitIndex;
begin
  // Ohne Typargumente gewinnt ein nicht generischer Typ jeder Unit vor einem generischen gleichen Namens, wie im
  // Compiler: TList ist mit System.Classes und System.Generics.Collections in uses immer System.Classes.TList (#981).
  if AOnlyTypes and (AArity = 0) and
    LookupGlobal(AUnit, AName, AWithImplementation, True, AResult, cNonGenericArity) then
  begin
    Exit(True);
  end;
  if LookupInUnit(AUnit, AName, not AWithImplementation, AOnlyTypes, AResult, AArity) then
  begin
    Exit(True);
  end;
  // Je Bezeichner über alle uses-Units: nur Verweise, keine Kopien der Units.
  for mUnitName in FUnits.ScopeUnits(AUnit, AWithImplementation) do
  begin
    if FUnits.FindUnitRef(mUnitName, mUsed) and LookupInUnit(mUsed^, AName, True, AOnlyTypes, AResult, AArity) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverLookup.ResolveTypeName(const ATypeName: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol; AArity: Integer): Boolean;
var
  mDot: Integer;
  mQualifier: TUnitIndex;
begin
  Result := False;
  if ATypeName = '' then
  begin
    Exit;
  end;
  // Unit.Typ
  mDot := LastDelimiter('.', ATypeName);
  if mDot = 0 then
  begin
    Result := LookupGlobal(AFromUnit, ATypeName, AWithImplementation, True, AResult, AArity);
  end
  else if FUnits.FindUnit(Copy(ATypeName, 1, mDot - 1), mQualifier) then
  begin
    Result := LookupInUnit(mQualifier, Copy(ATypeName, mDot + 1, MaxInt),
      not FPlace.IsCurrentFile(mQualifier.FileName), True, AResult, AArity);
  end;
end;

function TResolverLookup.ResolveTypeText(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean; out AResult: TResolvedSymbol): Boolean;
var
  mBase, mArgs: string;
  mArgList: TArray<string>;
  mIndex: Integer;
begin
  TResolverText.SplitGeneric(AText, mBase, mArgs);
  mArgList := TResolverText.SplitArgs(mArgs);
  Result := ResolveTypeName(mBase, AFromUnit, AWithImplementation, AResult, Length(mArgList));
  if not Result then
  begin
    if (mArgs = '') and TResolverText.IsBuiltinName(mBase) then
    begin
      AResult := TResolvedSymbol.BuiltinOf(mBase);
      Result := True;
    end;
    Exit;
  end;
  if Length(mArgList) > 0 then
  begin
    // Typargumente gelten dort, wo sie stehen: vor dem Einsetzen in fremden Units qualifizieren.
    for mIndex := 0 to High(mArgList) do
    begin
      mArgList[mIndex] := QualifyType(mArgList[mIndex], AFromUnit, AWithImplementation);
    end;
    AResult.Bindings := TResolverText.Bind(AResult.TypeParams, mArgList);
  end;
end;

function TResolverLookup.QualifyType(const AText: string; const AFromUnit: TUnitIndex;
  AWithImplementation: Boolean): string;
var
  mBase, mArgs: string;
  mArgList: TArray<string>;
  mResolved: TResolvedSymbol;
  mIndex: Integer;
begin
  TResolverText.SplitGeneric(AText, mBase, mArgs);
  mArgList := TResolverText.SplitArgs(mArgs);
  Result := mBase;
  if (Pos('.', mBase) = 0) and ResolveTypeName(mBase, AFromUnit, AWithImplementation, mResolved, Length(mArgList)) and
    (mResolved.Kind = TResolvedKind.Symbol) and (mResolved.Container = '') then
  begin
    Result := mResolved.UnitName + '.' + mResolved.Name;
  end;
  if Length(mArgList) > 0 then
  begin
    for mIndex := 0 to High(mArgList) do
    begin
      mArgList[mIndex] := QualifyType(mArgList[mIndex], AFromUnit, AWithImplementation);
    end;
    Result := Result + '<' + string.Join(',', mArgList) + '>';
  end;
end;

end.
