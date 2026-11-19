unit Atlas.Core.Debug.WatchScopes;

// Überwachte Ausdrücke je Klasse oder Unit im Fenster „Variablen“ (#2550), ohne IDE:
//   - TAtlasWatchScope: Bindung eines Ausdrucks: überall, an eine Klasse („class:TAuftragsLauf“) oder an eine Unit
//     („unit:Auftrag.Lauf“); so steht sie im Feld scope der Ablage. Unbekanntes gilt als überall.
//   - TAtlasWatchPlace: wo das Programm hält: Unit, Klasse der Methode und ihre Vorfahren. Aus der Antwort von
//     atlas.server.debugVariables (unit, class, ancestors); ohne Server aus dem Rahmen der IDE
//     („Auftrag.Lauf.TAuftragsLauf.LeseBericht“ in Auftrag.Lauf.pas), dann ohne Vorfahren. Eine Bindung an eine
//     Klasse gilt auch in ihren Nachfahren, soweit die Vorfahren bekannt sind.
//   - TAtlasWatchArrange: was der Reiter Überwachung zeigt: erst die passenden gebundenen, dann die überall
//     geltenden, jeweils in der Reihenfolge des Hinzufügens; die übrigen sind ausgeblendet und stehen auf Wunsch
//     danach. Ohne bekannten Ort (kein Rahmen mit Quelltext) passt keine Bindung.

interface

uses
  System.JSON;

{$SCOPEDENUMS ON}

type
  TAtlasWatchScopeKind = (Everywhere, ClassType, UnitName);

  TAtlasWatchScope = record
    Kind: TAtlasWatchScopeKind;
    /// <summary>Klasse bzw. Unit; '' bei Everywhere.</summary>
    Name: string;
    class function Everywhere: TAtlasWatchScope; static;
    class function ForClass(const AName: string): TAtlasWatchScope; static;
    class function ForUnit(const AName: string): TAtlasWatchScope; static;
    /// <summary>Aus dem Feld scope der Ablage; leer oder unbekannt: überall.</summary>
    class function Parse(const AText: string): TAtlasWatchScope; static;
    /// <summary>Für das Feld scope; '' bei Everywhere.</summary>
    function ToText: string;
    function Same(const AOther: TAtlasWatchScope): Boolean;
  end;

  TAtlasWatchPlace = record
    UnitName: string;
    /// <summary>Klasse der Methode; '' in freien Routinen.</summary>
    TypeName: string;
    /// <summary>Vorfahren, nächster zuerst; leer, wenn unbekannt.</summary>
    Ancestors: TArray<string>;
    /// <summary>Aus der Antwort von atlas.server.debugVariables; leer, wenn sie keine Felder dazu hat.</summary>
    class function Read(AJson: TJSONObject): TAtlasWatchPlace; static;
    /// <summary>Aus der Routine eines Rahmens („Unit.TKlasse.Methode“) und seiner Datei.</summary>
    class function FromFrame(const ARoutine, AFileName: string): TAtlasWatchPlace; static;
    /// <summary>Ist bekannt, wo das Programm hält?</summary>
    function Known: Boolean;
    /// <summary>Gilt ein Ausdruck mit AScope hier?</summary>
    function Matches(const AScope: TAtlasWatchScope): Boolean;
    /// <summary>Bindung an die Klasse bzw. Unit des Halts; Everywhere, wenn es sie nicht gibt.</summary>
    function ScopeOf(AKind: TAtlasWatchScopeKind): TAtlasWatchScope;
  end;

  TAtlasScopedWatch = record
    Expression: string;
    Scope: TAtlasWatchScope;
    class function Create(const AExpression: string; const AScope: TAtlasWatchScope): TAtlasScopedWatch; static;
  end;

  TAtlasScopedWatches = TArray<TAtlasScopedWatch>;

  /// <summary>Was der Reiter Überwachung zeigt.</summary>
  TAtlasWatchArrangement = record
    /// <summary>Gezeigte Ausdrücke in Reihenfolge.</summary>
    Shown: TAtlasScopedWatches;
    /// <summary>So viele sind ausgeblendet (nicht in Shown, außer mit AShowHidden).</summary>
    Hidden: Integer;
    function Expressions: TArray<string>;
  end;

  TAtlasWatchArrange = record
  public
    /// <summary>AWatches in der Reihenfolge des Hinzufügens. AEnabled aus: alle wie bisher in dieser Reihenfolge.
    /// AShowHidden: ausgeblendete hinten anhängen (sie zählen trotzdem in Hidden).</summary>
    class function Arrange(const AWatches: TAtlasScopedWatches; const APlace: TAtlasWatchPlace;
      AEnabled, AShowHidden: Boolean): TAtlasWatchArrangement; static;
  end;

{$SCOPEDENUMS OFF}

implementation

uses
  System.SysUtils,
  Atlas.Text.Json;

const
  cClassPrefix = 'class:';
  cUnitPrefix = 'unit:';

/// <summary>Dateiname ohne Ordner und Endung; trennt an \ und / (der Debugger liefert Windows-Pfade).</summary>
function UnitOfFile(const AFileName: string): string;
var
  mStart, mDot: Integer;
begin
  mStart := LastDelimiter('\/', AFileName);
  Result := Copy(AFileName, mStart + 1, MaxInt);
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, 1, mDot - 1);
  end;
end;

/// <summary>Teil vor dem letzten Punkt außerhalb spitzer Klammern, ohne Typparameter; '' ohne Punkt.</summary>
function OwnerOf(const ARoutine: string): string;
var
  mDepth, mIndex, mDot: Integer;
begin
  mDepth := 0;
  mDot := 0;
  for mIndex := 1 to Length(ARoutine) do
  begin
    case ARoutine[mIndex] of
      '<':
        Inc(mDepth);
      '>':
        Dec(mDepth);
      '.':
        if mDepth = 0 then
        begin
          mDot := mIndex;
        end;
    end;
  end;
  Result := '';
  // Generische Klassen und solche in Klammern: zu unsicher, der Ausdruck gilt dann nur für die Unit.
  if (mDot > 1) and (Pos('<', Copy(ARoutine, 1, mDot - 1)) = 0) then
  begin
    Result := Copy(ARoutine, 1, mDot - 1);
  end;
end;

{ TAtlasWatchScope }

class function TAtlasWatchScope.Everywhere: TAtlasWatchScope;
begin
  Result := Default(TAtlasWatchScope);
end;

class function TAtlasWatchScope.ForClass(const AName: string): TAtlasWatchScope;
begin
  Result := Everywhere;
  if Trim(AName) <> '' then
  begin
    Result.Kind := TAtlasWatchScopeKind.ClassType;
    Result.Name := Trim(AName);
  end;
end;

class function TAtlasWatchScope.ForUnit(const AName: string): TAtlasWatchScope;
begin
  Result := Everywhere;
  if Trim(AName) <> '' then
  begin
    Result.Kind := TAtlasWatchScopeKind.UnitName;
    Result.Name := Trim(AName);
  end;
end;

class function TAtlasWatchScope.Parse(const AText: string): TAtlasWatchScope;
var
  mText: string;
begin
  mText := Trim(AText);
  if SameText(Copy(mText, 1, Length(cClassPrefix)), cClassPrefix) then
  begin
    Result := ForClass(Copy(mText, Length(cClassPrefix) + 1, MaxInt));
  end
  else if SameText(Copy(mText, 1, Length(cUnitPrefix)), cUnitPrefix) then
  begin
    Result := ForUnit(Copy(mText, Length(cUnitPrefix) + 1, MaxInt));
  end
  else
  begin
    Result := Everywhere;
  end;
end;

function TAtlasWatchScope.ToText: string;
begin
  case Kind of
    TAtlasWatchScopeKind.ClassType:
      Result := cClassPrefix + Name;
    TAtlasWatchScopeKind.UnitName:
      Result := cUnitPrefix + Name;
  else
    Result := '';
  end;
end;

function TAtlasWatchScope.Same(const AOther: TAtlasWatchScope): Boolean;
begin
  Result := (Kind = AOther.Kind) and SameText(Name, AOther.Name);
end;

{ TAtlasWatchPlace }

class function TAtlasWatchPlace.Read(AJson: TJSONObject): TAtlasWatchPlace;
begin
  Result := Default(TAtlasWatchPlace);
  if AJson = nil then
  begin
    Exit;
  end;
  Result.UnitName := TJsonRead.TrimmedText(AJson, 'unit');
  Result.TypeName := TJsonRead.TrimmedText(AJson, 'class');
  Result.Ancestors := TJsonRead.TrimmedStrings(AJson, 'ancestors');
end;

class function TAtlasWatchPlace.FromFrame(const ARoutine, AFileName: string): TAtlasWatchPlace;
var
  mRoutine: string;
begin
  Result := Default(TAtlasWatchPlace);
  Result.UnitName := UnitOfFile(AFileName);
  mRoutine := Trim(ARoutine);
  if Result.UnitName = '' then
  begin
    Exit;
  end;
  // „Auftrag.Lauf.TAuftragsLauf.LeseBericht“: erst die Unit ab, dann die Methode.
  if SameText(Copy(mRoutine, 1, Length(Result.UnitName) + 1), Result.UnitName + '.') then
  begin
    mRoutine := Copy(mRoutine, Length(Result.UnitName) + 2, MaxInt);
    Result.TypeName := OwnerOf(mRoutine);
  end;
end;

function TAtlasWatchPlace.Known: Boolean;
begin
  Result := UnitName <> '';
end;

function TAtlasWatchPlace.Matches(const AScope: TAtlasWatchScope): Boolean;
var
  mAncestor: string;
begin
  case AScope.Kind of
    TAtlasWatchScopeKind.ClassType:
      begin
        Result := (TypeName <> '') and SameText(TypeName, AScope.Name);
        if Result or (TypeName = '') then
        begin
          Exit;
        end;
        for mAncestor in Ancestors do
        begin
          if SameText(mAncestor, AScope.Name) then
          begin
            Exit(True);
          end;
        end;
      end;
    TAtlasWatchScopeKind.UnitName:
      Result := Known and SameText(UnitName, AScope.Name);
  else
    Result := True;
  end;
end;

function TAtlasWatchPlace.ScopeOf(AKind: TAtlasWatchScopeKind): TAtlasWatchScope;
begin
  case AKind of
    TAtlasWatchScopeKind.ClassType:
      Result := TAtlasWatchScope.ForClass(TypeName);
    TAtlasWatchScopeKind.UnitName:
      Result := TAtlasWatchScope.ForUnit(UnitName);
  else
    Result := TAtlasWatchScope.Everywhere;
  end;
end;

{ TAtlasScopedWatch }

class function TAtlasScopedWatch.Create(const AExpression: string;
  const AScope: TAtlasWatchScope): TAtlasScopedWatch;
begin
  Result.Expression := Trim(AExpression);
  Result.Scope := AScope;
end;

{ TAtlasWatchArrangement }

function TAtlasWatchArrangement.Expressions: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Shown));
  for mIndex := 0 to High(Shown) do
  begin
    Result[mIndex] := Shown[mIndex].Expression;
  end;
end;

{ TAtlasWatchArrange }

class function TAtlasWatchArrange.Arrange(const AWatches: TAtlasScopedWatches; const APlace: TAtlasWatchPlace;
  AEnabled, AShowHidden: Boolean): TAtlasWatchArrangement;
var
  mBound, mGeneral, mHidden: TAtlasScopedWatches;
  mWatch: TAtlasScopedWatch;
begin
  Result := Default(TAtlasWatchArrangement);
  if not AEnabled then
  begin
    Result.Shown := Copy(AWatches);
    Exit;
  end;
  mBound := nil;
  mGeneral := nil;
  mHidden := nil;
  for mWatch in AWatches do
  begin
    if mWatch.Scope.Kind = TAtlasWatchScopeKind.Everywhere then
    begin
      mGeneral := mGeneral + [mWatch];
    end
    else if APlace.Matches(mWatch.Scope) then
    begin
      mBound := mBound + [mWatch];
    end
    else
    begin
      mHidden := mHidden + [mWatch];
    end;
  end;
  Result.Shown := mBound + mGeneral;
  Result.Hidden := Length(mHidden);
  if AShowHidden then
  begin
    Result.Shown := Result.Shown + mHidden;
  end;
end;

end.
