unit Atlas.Core.Designer.EventMap;

// Ereignis-Karte des Formulars (#612), ohne VCL und Windows:
// - Zuweisungen aus dem Formulartext (TAtlasFormModel, Ereignisse On… mit
//   einem Bezeichner), Handler aus der Unit (veröffentlichte Methoden der
//   Formularklasse vor dem ersten Sichtbarkeitsabschnitt bzw. unter
//   „published“, mit Zeile und Zeilenzahl des Rumpfs).
// - Befunde: leerer Handler (nur begin/end und Kommentare), Handler ohne
//   Zuweisung (veröffentlicht, mit Parameter Sender, in keiner Zuweisung),
//   Zuweisung auf eine Methode, die es in der Klasse nicht gibt.
// - Gruppierung nach Komponente, Ereignis oder Handler; Filter nach Text
//   (Komponente oder Handler), Ereignis und „nur Befunde“.

interface

uses
  Atlas.Core.Designer.FormModel;

type
{$SCOPEDENUMS ON}
  TAtlasEventFinding = (None, Empty, Unassigned, Missing);
  TAtlasEventGroup = (Component, Event, Handler);
{$SCOPEDENUMS OFF}

  TAtlasEventHandler = record
    Name: string;
    /// <summary>Zeile des Methodenkopfs im Implementierungsteil (0-basiert); -1 ohne Rumpf.</summary>
    Line: Integer;
    /// <summary>Zeilen des Rumpfs samt Kopf; 0 ohne Rumpf.</summary>
    Lines: Integer;
    Empty: Boolean;
    /// <summary>Hat den Parameter Sender, sieht also wie ein Ereignis-Handler aus.</summary>
    IsEvent: Boolean;
  end;

  TAtlasEventRow = record
    /// <summary>'' bei einem Handler ohne Zuweisung.</summary>
    Component: string;
    ClassName: string;
    Event: string;
    Handler: string;
    Line: Integer;
    Lines: Integer;
    Finding: TAtlasEventFinding;
    /// <summary>Zuweisungen mit diesem Handler im Formular.</summary>
    UseCount: Integer;
  end;

  TAtlasEventMap = class
  public
    /// <summary>Veröffentlichte Methoden der Klasse AFormClass in AUnit mit ihrem Rumpf.</summary>
    class function Handlers(const AUnit, AFormClass: string): TArray<TAtlasEventHandler>; static;
    /// <summary>Eine Zeile je Zuweisung, danach je Ereignis-Handler ohne Zuweisung.</summary>
    class function Rows(const AObjects: TArray<TAtlasFormObject>;
      const AHandlers: TArray<TAtlasEventHandler>): TArray<TAtlasEventRow>; static;
    /// <summary>AText in Komponente oder Handler; AEvent leer = alle Ereignisse.</summary>
    class function Filter(const ARows: TArray<TAtlasEventRow>; const AText, AEvent: string;
      AOnlyFindings: Boolean): TArray<TAtlasEventRow>; static;
    class function GroupKey(const ARow: TAtlasEventRow; AGroup: TAtlasEventGroup): string; static;
    /// <summary>Nach dem Schlüssel von AGroup sortiert, sonst in der Reihenfolge von ARows.</summary>
    class function Sorted(const ARows: TArray<TAtlasEventRow>; AGroup: TAtlasEventGroup): TArray<TAtlasEventRow>;
      static;
    /// <summary>Vorkommende Ereignisse, sortiert, ohne Doppelte.</summary>
    class function Events(const ARows: TArray<TAtlasEventRow>): TArray<string>; static;
    /// <summary>Zeilen von AHandler: Deklaration ADecl, Rumpf AFirst..ALast (samt einer Leerzeile, die sonst doppelt
    /// stünde); False ohne Deklaration oder Rumpf.</summary>
    class function HandlerRange(const AUnit, AFormClass, AHandler: string; out ADecl, AFirst, ALast: Integer): Boolean;
      static;
    /// <summary>AUnit ohne Deklaration und Rumpf von AHandler; AUnit unverändert, wenn es ihn nicht gibt.</summary>
    class function RemoveHandler(const AUnit, AFormClass, AHandler: string): string; static;
    /// <summary>Text ohne Kommentare, Leerraum und Großschreibung (für „leer“).</summary>
    class function Skeleton(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Core.Designer.FormUnit;

const
  cEmptyBody = 'beginend;';

class function TAtlasEventMap.Skeleton(const AText: string): string;
var
  mIndex: Integer;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if AText[mIndex] = '{' then
      begin
        mIndex := PosEx('}', AText, mIndex + 1);
        if mIndex = 0 then
        begin
          Break;
        end;
      end
      else if Copy(AText, mIndex, 2) = '(*' then
      begin
        mIndex := PosEx('*)', AText, mIndex + 2);
        if mIndex = 0 then
        begin
          Break;
        end;
        Inc(mIndex);
      end
      else if Copy(AText, mIndex, 2) = '//' then
      begin
        mIndex := PosEx(#10, AText, mIndex + 2);
        if mIndex = 0 then
        begin
          Break;
        end;
      end
      else if AText[mIndex] > ' ' then
      begin
        mBuilder.Append(AText[mIndex]);
      end;
      Inc(mIndex);
    end;
    Result := LowerCase(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

function IsSection(const AText: string; out APublished: Boolean): Boolean;
begin
  APublished := SameText(AText, 'published');
  Result := APublished or SameText(AText, 'private') or SameText(AText, 'protected') or SameText(AText, 'public') or
    SameText(AText, 'strict private') or SameText(AText, 'strict protected');
end;

class function TAtlasEventMap.Handlers(const AUnit, AFormClass: string): TArray<TAtlasEventHandler>;
var
  mUnit: TAtlasFormUnit;
  mFirst, mLast, mIndex, mBodyFirst, mBodyLast: Integer;
  mPublished, mIsMethod, mSection: Boolean;
  mHandler: TAtlasEventHandler;
  mName: string;
begin
  Result := nil;
  mUnit := TAtlasFormUnit.Create(AUnit);
  if not mUnit.FindClass(AFormClass, mFirst, mLast) then
  begin
    Exit;
  end;
  // Ohne Abschnitt sind die Elemente der Formularklasse veröffentlicht ({$M+} über TPersistent).
  mPublished := True;
  for mIndex := mFirst + 1 to mLast - 1 do
  begin
    if IsSection(mUnit.Lines[mIndex].Trim, mSection) then
    begin
      mPublished := mSection;
      Continue;
    end;
    mName := TAtlasFormUnit.MemberName(mUnit.Lines[mIndex], mIsMethod);
    if not mPublished or not mIsMethod or (mName = '') then
    begin
      Continue;
    end;
    mHandler := Default(TAtlasEventHandler);
    mHandler.Name := mName;
    mHandler.Line := -1;
    mHandler.IsEvent := ContainsText(mUnit.Lines[mIndex], '(Sender:');
    if mUnit.FindBody(AFormClass, mName, mBodyFirst, mBodyLast) then
    begin
      mHandler.Line := mBodyFirst;
      mHandler.Lines := mBodyLast - mBodyFirst + 1;
      mHandler.Empty := Skeleton(string.Join(#10, Copy(mUnit.Lines, mBodyFirst + 1,
        mBodyLast - mBodyFirst))) = cEmptyBody;
    end;
    Result := Result + [mHandler];
  end;
end;

function HandlerIndex(const AHandlers: TArray<TAtlasEventHandler>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AHandlers) do
  begin
    if SameText(AHandlers[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Zeile einer Zuweisung; AUsed markiert den gefundenen Handler.</summary>
function AssignedRow(const AObject: TAtlasFormObject; const AEvent: TAtlasFormValue;
  const AHandlers: TArray<TAtlasEventHandler>; var AUsed: TArray<Boolean>): TAtlasEventRow;
var
  mHandler: Integer;
begin
  Result := Default(TAtlasEventRow);
  Result.Component := AObject.Name;
  Result.ClassName := AObject.TypeName;
  Result.Event := AEvent.Path;
  Result.Handler := AEvent.Value;
  Result.Line := -1;
  mHandler := HandlerIndex(AHandlers, AEvent.Value);
  if mHandler < 0 then
  begin
    Result.Finding := TAtlasEventFinding.Missing;
    Exit;
  end;
  AUsed[mHandler] := True;
  Result.Line := AHandlers[mHandler].Line;
  Result.Lines := AHandlers[mHandler].Lines;
  if AHandlers[mHandler].Empty then
  begin
    Result.Finding := TAtlasEventFinding.Empty;
  end;
end;

function UnassignedRow(const AHandler: TAtlasEventHandler): TAtlasEventRow;
begin
  Result := Default(TAtlasEventRow);
  Result.Handler := AHandler.Name;
  Result.Line := AHandler.Line;
  Result.Lines := AHandler.Lines;
  Result.Finding := TAtlasEventFinding.Unassigned;
end;

/// <summary>Je Zeile: wie viele Zuweisungen denselben Handler nutzen.</summary>
procedure CountUses(var ARows: TArray<TAtlasEventRow>);
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to High(ARows) do
  begin
    for mOther := 0 to High(ARows) do
    begin
      if (ARows[mOther].Component <> '') and SameText(ARows[mOther].Handler, ARows[mIndex].Handler) then
      begin
        Inc(ARows[mIndex].UseCount);
      end;
    end;
  end;
end;

class function TAtlasEventMap.Rows(const AObjects: TArray<TAtlasFormObject>;
  const AHandlers: TArray<TAtlasEventHandler>): TArray<TAtlasEventRow>;
var
  mObject: TAtlasFormObject;
  mEvent: TAtlasFormValue;
  mHandler: Integer;
  mUsed: TArray<Boolean>;
begin
  Result := nil;
  SetLength(mUsed, Length(AHandlers));
  for mObject in AObjects do
  begin
    for mEvent in mObject.Events do
    begin
      Result := Result + [AssignedRow(mObject, mEvent, AHandlers, mUsed)];
    end;
  end;
  for mHandler := 0 to High(AHandlers) do
  begin
    if not mUsed[mHandler] and AHandlers[mHandler].IsEvent then
    begin
      Result := Result + [UnassignedRow(AHandlers[mHandler])];
    end;
  end;
  CountUses(Result);
end;

/// <summary>Text in Komponente oder Handler, Ereignis gleich, nur Befunde.</summary>
function Matches(const ARow: TAtlasEventRow; const AText, AEvent: string; AOnlyFindings: Boolean): Boolean;
begin
  Result := (AText = '') or ContainsText(ARow.Component, AText) or ContainsText(ARow.Handler, AText);
  Result := Result and ((AEvent = '') or SameText(ARow.Event, AEvent));
  Result := Result and (not AOnlyFindings or (ARow.Finding <> TAtlasEventFinding.None));
end;

class function TAtlasEventMap.Filter(const ARows: TArray<TAtlasEventRow>; const AText, AEvent: string;
  AOnlyFindings: Boolean): TArray<TAtlasEventRow>;
var
  mRow: TAtlasEventRow;
begin
  Result := nil;
  for mRow in ARows do
  begin
    if Matches(mRow, AText, AEvent, AOnlyFindings) then
    begin
      Result := Result + [mRow];
    end;
  end;
end;

class function TAtlasEventMap.GroupKey(const ARow: TAtlasEventRow; AGroup: TAtlasEventGroup): string;
begin
  case AGroup of
    TAtlasEventGroup.Event:
      Result := ARow.Event;
    TAtlasEventGroup.Handler:
      Result := ARow.Handler;
  else
    Result := ARow.Component;
  end;
end;

class function TAtlasEventMap.Sorted(const ARows: TArray<TAtlasEventRow>;
  AGroup: TAtlasEventGroup): TArray<TAtlasEventRow>;
var
  mIndex, mPlace: Integer;
  mRow: TAtlasEventRow;
begin
  // Einfügen hält die Reihenfolge gleicher Schlüssel (Reihenfolge im Formular).
  Result := Copy(ARows);
  for mIndex := 1 to High(Result) do
  begin
    mRow := Result[mIndex];
    mPlace := mIndex;
    while (mPlace > 0) and (CompareText(GroupKey(Result[mPlace - 1], AGroup), GroupKey(mRow, AGroup)) > 0) do
    begin
      Result[mPlace] := Result[mPlace - 1];
      Dec(mPlace);
    end;
    Result[mPlace] := mRow;
  end;
end;

class function TAtlasEventMap.Events(const ARows: TArray<TAtlasEventRow>): TArray<string>;
var
  mRow: TAtlasEventRow;
  mIndex, mPlace: Integer;
  mKnown: Boolean;
  mEvent: string;
begin
  Result := nil;
  for mRow in ARows do
  begin
    mKnown := mRow.Event = '';
    for mEvent in Result do
    begin
      mKnown := mKnown or SameText(mEvent, mRow.Event);
    end;
    if not mKnown then
    begin
      Result := Result + [mRow.Event];
    end;
  end;
  for mIndex := 1 to High(Result) do
  begin
    mEvent := Result[mIndex];
    mPlace := mIndex;
    while (mPlace > 0) and (CompareText(Result[mPlace - 1], mEvent) > 0) do
    begin
      Result[mPlace] := Result[mPlace - 1];
      Dec(mPlace);
    end;
    Result[mPlace] := mEvent;
  end;
end;

class function TAtlasEventMap.HandlerRange(const AUnit, AFormClass, AHandler: string; out ADecl, AFirst,
  ALast: Integer): Boolean;
var
  mUnit: TAtlasFormUnit;
  mClassFirst, mClassLast, mIndex: Integer;
  mIsMethod: Boolean;
begin
  ADecl := -1;
  mUnit := TAtlasFormUnit.Create(AUnit);
  Result := mUnit.FindBody(AFormClass, AHandler, AFirst, ALast) and
    mUnit.FindClass(AFormClass, mClassFirst, mClassLast);
  if not Result then
  begin
    Exit;
  end;
  // Leerzeile danach mitnehmen, wenn davor schon eine steht: keine doppelte Leerzeile.
  if (AFirst > 0) and (ALast + 1 < Length(mUnit.Lines)) and (mUnit.Lines[ALast + 1].Trim = '') and
    (mUnit.Lines[AFirst - 1].Trim = '') then
  begin
    Inc(ALast);
  end;
  for mIndex := mClassFirst + 1 to mClassLast - 1 do
  begin
    if SameText(TAtlasFormUnit.MemberName(mUnit.Lines[mIndex], mIsMethod), AHandler) and mIsMethod then
    begin
      ADecl := mIndex;
      Break;
    end;
  end;
  Result := ADecl >= 0;
end;

class function TAtlasEventMap.RemoveHandler(const AUnit, AFormClass, AHandler: string): string;
var
  mUnit: TAtlasFormUnit;
  mDecl, mFirst, mLast: Integer;
begin
  Result := AUnit;
  if not HandlerRange(AUnit, AFormClass, AHandler, mDecl, mFirst, mLast) then
  begin
    Exit;
  end;
  mUnit := TAtlasFormUnit.Create(AUnit);
  // Erst hinten (Rumpf), dann vorn (Deklaration).
  Delete(mUnit.Lines, mFirst, mLast - mFirst + 1);
  Delete(mUnit.Lines, mDecl, 1);
  Result := mUnit.Text;
end;

end.
