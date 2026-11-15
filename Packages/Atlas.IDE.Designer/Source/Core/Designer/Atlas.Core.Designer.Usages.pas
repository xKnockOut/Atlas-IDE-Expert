unit Atlas.Core.Designer.Usages;

// Verwendungen einer Komponente im Code (#750), ohne IDE:
// - KindAt ordnet einen Fundort der Referenzsuche ein: „schreibt“ bei einer
//   Zuweisung an die Komponente oder eine Eigenschaft, „Ereignis“ bei einer
//   Zuweisung an eine On…-Eigenschaft, „übergibt“, wenn die Komponente selbst
//   ohne Eigenschaft dasteht (Argument, Sender-Vergleich, with, rechte Seite
//   einer Zuweisung), sonst „liest“ (Eigenschaft gelesen, Methode gerufen).
// - FieldLine findet die Felddeklaration in der Formular-Klasse; von dort
//   fragt die IDE die Referenzsuche.
// - HandlerLine findet die Implementierung eines Handlers aus der DFM.
// - Bindings findet Eigenschaften anderer Komponenten, die in der DFM auf die
//   Komponente zeigen (PopupMenu, Menu, Images, DataSource …).
// - InScope filtert nach Suchbereich: Unit des Formulars, Projekt,
//   Projektgruppe; ScopeOf liest ihn aus der Einstellung, CountInScope zählt.
// - GroupCaption, HandlerOf, BindingOwner und FormOf bauen die Einträge des
//   Ergebnisfensters und den Text des Zählers.
// - TAtlasUsageWatch entprellt den Zähler im Statusfeld nach einem
//   Auswahlwechsel.

interface

uses
  System.Classes;

type
{$SCOPEDENUMS ON}
  TAtlasUsageKind = (Reads, Writes, Passes, Event);
  TAtlasUsageScope = (UnitOnly, Project, ProjectGroup);
  /// <summary>Wortform eines Zählers: keiner, einer, mehrere.</summary>
  TAtlasUsageForm = (None, One, Many);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Zugriff auf eine Komponente im Code; Line und Character 0-basiert.</summary>
  TAtlasUsage = record
    Component: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    Kind: TAtlasUsageKind;
    /// <summary>Methode, in der die Zeile liegt; '' außerhalb.</summary>
    Method: string;
    Preview: string;
  end;

  TAtlasDesignerUsages = class
  public
    /// <summary>Art des Zugriffs auf den Namen, der in ALine an ACharacter (0-basiert) beginnt.</summary>
    class function KindAt(const ALine: string; ACharacter: Integer): TAtlasUsageKind; static;
    /// <summary>Zeile (0-basiert) der Felddeklaration AName in der Klasse AClassName; -1 ohne. ACharacter: Beginn
    /// des Namens (0-basiert).</summary>
    class function FieldLine(const ALines: TArray<string>; const AClassName, AName: string;
      out ACharacter: Integer): Integer; static;
    /// <summary>Zeile (0-basiert) von „procedure AClassName.AMethod“ im Implementierungsteil; -1 ohne.</summary>
    class function HandlerLine(const ALines: TArray<string>; const AClassName, AMethod: string): Integer; static;
    /// <summary>Gehört AFileName zum Bereich? AProjectFiles: Dateien des aktiven Projekts.</summary>
    class function InScope(AScope: TAtlasUsageScope; const AFileName, AFormUnit: string;
      const AProjectFiles: TArray<string>): Boolean; static;
    /// <summary>Nach Komponente, Datei und Zeile geordnet.</summary>
    class function Sorted(const AUsages: TArray<TAtlasUsage>): TArray<TAtlasUsage>; static;
    /// <summary>Bindungen aus der DFM: Eigenschaften von ARoot und seinen Komponenten, die auf ATarget zeigen
    /// („Panel1.PopupMenu“, „Form1.Menu“); nur Eigenschaften, die direkt ein Feld lesen.</summary>
    class function Bindings(ARoot, ATarget: TComponent): TArray<string>; static;
    /// <summary>Suchbereich aus dem Wert der Einstellung; AUnitKey und AGroupKey: Werte für Unit bzw.
    /// Projektgruppe, alles andere ist Projekt.</summary>
    class function ScopeOf(const AValue, AUnitKey, AGroupKey: string): TAtlasUsageScope; static;
    /// <summary>Zahl der Dateien aus AFiles im Bereich (je Fundort ein Eintrag).</summary>
    class function CountInScope(AScope: TAtlasUsageScope; const AFiles: TArray<string>; const AFormUnit: string;
      const AProjectFiles: TArray<string>): Integer; static;
    /// <summary>Überschrift der Gruppe „Komponente · Datei · Methode“; AOutside für Fundorte außerhalb einer
    /// Methode.</summary>
    class function GroupCaption(const AUsage: TAtlasUsage; const AOutside: string): string; static;
    /// <summary>Methode aus „OnClick = Klick“.</summary>
    class function HandlerOf(const AEvent: string): string; static;
    /// <summary>Bindende Komponente aus „Panel1.PopupMenu“.</summary>
    class function BindingOwner(const ABinding: string): string; static;
    class function FormOf(ACount: Integer): TAtlasUsageForm; static;
  end;

  /// <summary>Entprellte Auswahl des Zählers: erst fragen, wenn dieselbe Auswahl cDebounceMs steht, und je
  /// Auswahl nur einmal.</summary>
  TAtlasUsageWatch = record
  public const
    cDebounceMs = 400;
  public
    /// <summary>Zuletzt gesehene Auswahl („Unit|Komponente“) und seit wann.</summary>
    Watched: string;
    Since: UInt64;
    /// <summary>Auswahl, für die der Zähler gefragt ist bzw. steht.</summary>
    Asked: string;
    class function KeyOf(const AUnitFile, AComponent: string): string; static;
    /// <summary>Auswahl AKey zur Zeit ANow gesehen; True, wenn jetzt zu fragen ist (merkt sie als gefragt).</summary>
    function Ask(const AKey: string; ANow: UInt64): Boolean;
    /// <summary>Unit der gefragten Auswahl.</summary>
    function AskedUnit: string;
    procedure Clear;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  System.TypInfo,
  Atlas.Text.Chars;

const
  /// <summary>Vorsilbe eines Ereignisnamens.</summary>
  cEventPrefix = 'On';
  /// <summary>Trenner zwischen Ereignis und Methode („OnClick = Klick“).</summary>
  cEventAssign = ' = ';
  cCaptionSeparator = ' · ';
  cKeySeparator = '|';

/// <summary>Leerzeichen ab APos (1-basiert) überspringen.</summary>
function SkipBlanks(const ALine: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result <= Length(ALine)) and ((ALine[Result] = ' ') or (ALine[Result] = #9)) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Hinter einer Klammer ab APos (1-basiert, auf „(“ oder „[“): Position nach der passenden schließenden.
/// </summary>
function SkipBracket(const ALine: string; APos: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := APos;
  while Result <= Length(ALine) do
  begin
    if CharInSet(ALine[Result], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(ALine[Result], [')', ']']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Result + 1);
      end;
    end;
    Inc(Result);
  end;
end;

/// <summary>Ende (1-basiert, hinter dem letzten Zeichen) des Bezeichners ab APos.</summary>
function IdentEnd(const ALine: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result <= Length(ALine)) and TTextChars.IsIdentChar(ALine[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Folgt der Kette „.Eigenschaft“, „[Index]“ und „(Argumente)“ hinter dem Namen. AMembers zählt die
/// Eigenschaften, ALast ist die letzte; Ergebnis: Position dahinter.</summary>
function FollowChain(const ALine: string; APos: Integer; out AMembers: Integer; out ALast: string): Integer;
var
  mNext, mStop: Integer;
begin
  AMembers := 0;
  ALast := '';
  Result := APos;
  while True do
  begin
    mNext := SkipBlanks(ALine, Result);
    if mNext > Length(ALine) then
    begin
      Exit;
    end;
    if CharInSet(ALine[mNext], ['(', '[']) then
    begin
      Result := SkipBracket(ALine, mNext);
      Continue;
    end;
    if ALine[mNext] <> '.' then
    begin
      Exit;
    end;
    mNext := SkipBlanks(ALine, mNext + 1);
    mStop := IdentEnd(ALine, mNext);
    if mStop = mNext then
    begin
      Exit;
    end;
    ALast := Copy(ALine, mNext, mStop - mNext);
    Inc(AMembers);
    Result := mStop;
  end;
end;

/// <summary>„OnClick“, „OnChange“: Name eines Ereignisses.</summary>
function IsEventName(const AName: string): Boolean;
begin
  Result := (Length(AName) > Length(cEventPrefix)) and StartsText(cEventPrefix, AName) and
    CharInSet(AName[Length(cEventPrefix) + 1], ['A'..'Z']);
end;

{ TAtlasDesignerUsages }

class function TAtlasDesignerUsages.KindAt(const ALine: string; ACharacter: Integer): TAtlasUsageKind;
var
  mPos, mMembers: Integer;
  mLast: string;
begin
  mPos := FollowChain(ALine, IdentEnd(ALine, ACharacter + 1), mMembers, mLast);
  mPos := SkipBlanks(ALine, mPos);
  if Copy(ALine, mPos, 2) = ':=' then
  begin
    if (mMembers > 0) and IsEventName(mLast) then
    begin
      Exit(TAtlasUsageKind.Event);
    end;
    Exit(TAtlasUsageKind.Writes);
  end;
  if mMembers = 0 then
  begin
    Result := TAtlasUsageKind.Passes;
  end
  else
  begin
    Result := TAtlasUsageKind.Reads;
  end;
end;

/// <summary>Beginnt in ALine die Klasse AClassName („TfrmX = class“)?</summary>
function StartsClass(const ALine, AClassName: string): Boolean;
var
  mText, mRest: string;
begin
  mText := Trim(ALine);
  if not StartsText(AClassName, mText) then
  begin
    Exit(False);
  end;
  mRest := LowerCase(StringReplace(Copy(mText, Length(AClassName) + 1, MaxInt), ' ', '', [rfReplaceAll]));
  // Vorwärtsdeklaration „TfrmX = class;“ hat keinen Rumpf.
  Result := StartsText('=class', mRest) and not StartsText('=class;', mRest) and not StartsText('=classof', mRest);
end;

/// <summary>Beginn (1-basiert) von AName in der Liste vor dem Doppelpunkt („a, b: TEdit“); 0 ohne.</summary>
function NameInFieldList(const ALine, AName: string): Integer;
var
  mColon, mPos, mStop: Integer;
begin
  Result := 0;
  mColon := Pos(':', ALine);
  if (mColon = 0) or (Copy(ALine, mColon, 2) = ':=') then
  begin
    Exit;
  end;
  mPos := SkipBlanks(ALine, 1);
  while mPos < mColon do
  begin
    mStop := IdentEnd(ALine, mPos);
    if mStop = mPos then
    begin
      Exit;
    end;
    if SameText(Copy(ALine, mPos, mStop - mPos), AName) then
    begin
      Exit(mPos);
    end;
    mPos := SkipBlanks(ALine, mStop);
    if (mPos < mColon) and (ALine[mPos] = ',') then
    begin
      mPos := SkipBlanks(ALine, mPos + 1);
    end
    else
    begin
      Exit;
    end;
  end;
end;

class function TAtlasDesignerUsages.FieldLine(const ALines: TArray<string>; const AClassName, AName: string;
  out ACharacter: Integer): Integer;
var
  mLine, mPos: Integer;
  mInClass: Boolean;
begin
  ACharacter := -1;
  mInClass := False;
  for mLine := 0 to High(ALines) do
  begin
    if not mInClass then
    begin
      mInClass := StartsClass(ALines[mLine], AClassName);
      Continue;
    end;
    if SameText(Trim(ALines[mLine]), 'end;') then
    begin
      Break;
    end;
    mPos := NameInFieldList(ALines[mLine], AName);
    if mPos > 0 then
    begin
      ACharacter := mPos - 1;
      Exit(mLine);
    end;
  end;
  Result := -1;
end;

class function TAtlasDesignerUsages.HandlerLine(const ALines: TArray<string>; const AClassName,
  AMethod: string): Integer;
var
  mLine: Integer;
  mText, mHead: string;
begin
  mHead := LowerCase(AClassName + '.' + AMethod);
  for mLine := 0 to High(ALines) do
  begin
    mText := LowerCase(Trim(ALines[mLine]));
    if StartsText('procedure ', mText) or StartsText('function ', mText) then
    begin
      mText := Trim(Copy(mText, Pos(' ', mText) + 1, MaxInt));
      if StartsText(mHead, mText) and ((Length(mText) = Length(mHead)) or
        not TTextChars.IsIdentChar(mText[Length(mHead) + 1])) then
      begin
        Exit(mLine);
      end;
    end;
  end;
  Result := -1;
end;

class function TAtlasDesignerUsages.InScope(AScope: TAtlasUsageScope; const AFileName, AFormUnit: string;
  const AProjectFiles: TArray<string>): Boolean;
var
  mFile: string;
begin
  if SameText(AFileName, AFormUnit) or (AScope = TAtlasUsageScope.ProjectGroup) then
  begin
    Exit(True);
  end;
  if AScope = TAtlasUsageScope.UnitOnly then
  begin
    Exit(False);
  end;
  for mFile in AProjectFiles do
  begin
    if SameText(mFile, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDesignerUsages.Sorted(const AUsages: TArray<TAtlasUsage>): TArray<TAtlasUsage>;
begin
  Result := Copy(AUsages);
  TArray.Sort<TAtlasUsage>(Result, TComparer<TAtlasUsage>.Construct(
    function(const ALeft, ARight: TAtlasUsage): Integer
    begin
      Result := CompareText(ALeft.Component, ARight.Component);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.FileName, ARight.FileName);
      end;
      if Result = 0 then
      begin
        Result := ALeft.Line - ARight.Line;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Character - ARight.Character;
      end;
    end));
end;

/// <summary>Veröffentlichte Objekt-Eigenschaften von AObject, die auf ATarget zeigen, als „APrefix.Name“.
/// Nur Eigenschaften, die direkt ein Feld lesen (PopupMenu, Images, DataSource …): Lesemethoden können im
/// Designer Nebenwirkungen haben oder auf freigegebene Objekte zeigen (Zugriffsverletzung in der IDE). Der Wert
/// wird nur als Zeiger verglichen, nie angefasst.</summary>
procedure CollectBindings(AObject: TObject; ATarget: TComponent; const APrefix: string;
  var AResult: TArray<string>);
var
  mList: PPropList;
  mCount, i: Integer;
  mGetter: NativeUInt;
  mValue: Pointer;
begin
  mCount := GetPropList(AObject, mList);
  try
    for i := 0 to mCount - 1 do
    begin
      if mList[i].PropType^.Kind <> tkClass then
      begin
        Continue;
      end;
      mGetter := NativeUInt(mList[i].GetProc);
      if (mGetter and PROPSLOT_MASK) <> PROPSLOT_FIELD then
      begin
        Continue;
      end;
      mValue := PPointer(PByte(AObject) + (mGetter and not PROPSLOT_MASK))^;
      if mValue = Pointer(ATarget) then
      begin
        AResult := AResult + [APrefix + '.' + string(mList[i].Name)];
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

class function TAtlasDesignerUsages.Bindings(ARoot, ATarget: TComponent): TArray<string>;
var
  i: Integer;
begin
  Result := nil;
  if (ARoot = nil) or (ATarget = nil) then
  begin
    Exit;
  end;
  if ARoot <> ATarget then
  begin
    CollectBindings(ARoot, ATarget, ARoot.Name, Result);
  end;
  for i := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[i] <> ATarget then
    begin
      CollectBindings(ARoot.Components[i], ATarget, ARoot.Components[i].Name, Result);
    end;
  end;
end;

class function TAtlasDesignerUsages.ScopeOf(const AValue, AUnitKey, AGroupKey: string): TAtlasUsageScope;
begin
  if SameText(AValue, AUnitKey) then
  begin
    Result := TAtlasUsageScope.UnitOnly;
  end
  else if SameText(AValue, AGroupKey) then
  begin
    Result := TAtlasUsageScope.ProjectGroup;
  end
  else
  begin
    Result := TAtlasUsageScope.Project;
  end;
end;

class function TAtlasDesignerUsages.CountInScope(AScope: TAtlasUsageScope; const AFiles: TArray<string>;
  const AFormUnit: string; const AProjectFiles: TArray<string>): Integer;
var
  mFile: string;
begin
  Result := 0;
  for mFile in AFiles do
  begin
    if InScope(AScope, mFile, AFormUnit, AProjectFiles) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasDesignerUsages.GroupCaption(const AUsage: TAtlasUsage; const AOutside: string): string;
var
  mMethod: string;
begin
  mMethod := AUsage.Method;
  if mMethod = '' then
  begin
    mMethod := AOutside;
  end;
  Result := AUsage.Component + cCaptionSeparator + ExtractFileName(AUsage.FileName) + cCaptionSeparator + mMethod;
end;

class function TAtlasDesignerUsages.HandlerOf(const AEvent: string): string;
begin
  Result := Copy(AEvent, Pos(cEventAssign, AEvent) + Length(cEventAssign), MaxInt);
end;

class function TAtlasDesignerUsages.BindingOwner(const ABinding: string): string;
begin
  Result := Copy(ABinding, 1, Pos('.', ABinding) - 1);
end;

class function TAtlasDesignerUsages.FormOf(ACount: Integer): TAtlasUsageForm;
begin
  if ACount = 1 then
  begin
    Result := TAtlasUsageForm.One;
  end
  else if ACount > 1 then
  begin
    Result := TAtlasUsageForm.Many;
  end
  else
  begin
    Result := TAtlasUsageForm.None;
  end;
end;

{ TAtlasUsageWatch }

class function TAtlasUsageWatch.KeyOf(const AUnitFile, AComponent: string): string;
begin
  Result := AUnitFile + cKeySeparator + AComponent;
end;

function TAtlasUsageWatch.Ask(const AKey: string; ANow: UInt64): Boolean;
begin
  Result := False;
  if AKey <> Watched then
  begin
    Watched := AKey;
    Since := ANow;
  end
  else if (Asked <> AKey) and (ANow - Since >= cDebounceMs) then
  begin
    Asked := AKey;
    Result := True;
  end;
end;

function TAtlasUsageWatch.AskedUnit: string;
begin
  Result := Copy(Asked, 1, Pos(cKeySeparator, Asked) - 1);
end;

procedure TAtlasUsageWatch.Clear;
begin
  Watched := '';
  Asked := '';
end;

end.
