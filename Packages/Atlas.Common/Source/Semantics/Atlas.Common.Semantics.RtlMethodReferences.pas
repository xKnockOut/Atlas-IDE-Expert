unit Atlas.Common.Semantics.RtlMethodReferences;

// Methodenreferenzen aus System.SysUtils (TProc, TProc<…>, TFunc<…>, TPredicate<T>) ohne Quelltext der RTL
// (#468, #2309). Ohne Delphi-Installation (Cloud, CI unter Linux) steht System.SysUtils nicht im Index; die
// Vervollständigung braucht die Köpfe trotzdem für ihr Gerüst, die Regel type-mismatch für ihre Prüfung von
// Routinen, die ohne () übergeben werden. Die Deklarationen entsprechen denen der RTL:
//   TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);
//   TFunc<T, TResult> = reference to function(Arg1: T): TResult;
//   TPredicate<T> = reference to function(Arg1: T): Boolean;
// Bis zu vier Parameter, wie in der RTL. Was der Index kennt, geht immer vor; diese Unit ergänzt nur.

interface

uses
  System.SysUtils;

type
  /// <summary>Ein Typ aus System.SysUtils mit eingesetzten Typargumenten.</summary>
  TRtlMethodReference = record
    /// <summary>TProc, TFunc oder TPredicate.</summary>
    Name: string;
    /// <summary>Deklaration wie im Index: "TProc&lt;T&gt; = reference to procedure(Arg1: T);".</summary>
    Signature: string;
    /// <summary>Bindungen der Typparameter wie im Index: "T=string".</summary>
    Bindings: TArray<string>;
  end;

  TRtlMethodReferences = class
  public const
    /// <summary>Höchstzahl der Parameter von TProc und TFunc in der RTL.</summary>
    cMaxParams = 4;
  public
    /// <summary>"TFunc&lt;TKunde, Boolean&gt;" → ABase "TFunc", Ergebnis [TKunde, Boolean]; ohne spitze Klammern leer.
    /// </summary>
    class function TypeArgs(const ATypeText: string; out ABase: string): TArray<string>; static;
    /// <summary>Deklaration aus System.SysUtils für ABase (ohne oder mit Unit) und AArgCount Typargumente; ''
    /// ohne.</summary>
    class function Declaration(const ABase: string; AArgCount: Integer): string; static;
    /// <summary>Typ ATypeText ("TProc&lt;string&gt;", "SysUtils.TFunc&lt;Integer&gt;", "TProc") als Typ aus
    /// System.SysUtils; False bei anderen Namen und unpassender Zahl der Typargumente.</summary>
    class function Find(const ATypeText: string; out AReference: TRtlMethodReference): Boolean; static;
    /// <summary>Ist AUnitName System.SysUtils (auch ohne Namespace)?</summary>
    class function IsSysUtils(const AUnitName: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

class function TRtlMethodReferences.TypeArgs(const ATypeText: string; out ABase: string): TArray<string>;
var
  mOpen, mIndex, mDepth, mStart: Integer;
  mText: string;
begin
  Result := nil;
  mText := Trim(ATypeText);
  mOpen := Pos('<', mText);
  if (mOpen = 0) or not EndsStr('>', mText) then
  begin
    ABase := mText;
    Exit;
  end;
  ABase := Trim(Copy(mText, 1, mOpen - 1));
  mDepth := 0;
  mStart := mOpen + 1;
  for mIndex := mOpen + 1 to Length(mText) - 1 do
    case mText[mIndex] of
      '<', '(', '[':
        Inc(mDepth);
      '>', ')', ']':
        Dec(mDepth);
      ',':
        if mDepth = 0 then
        begin
          Result := Result + [Trim(Copy(mText, mStart, mIndex - mStart))];
          mStart := mIndex + 1;
        end;
    end;
  Result := Result + [Trim(Copy(mText, mStart, Length(mText) - mStart))];
end;

/// <summary>ABase ohne System.SysUtils. bzw. SysUtils. davor.</summary>
function RtlName(const ABase: string): string;
begin
  Result := ABase;
  if StartsText('System.SysUtils.', Result) then
  begin
    Result := Copy(Result, Length('System.SysUtils.') + 1, MaxInt);
  end
  else if StartsText('SysUtils.', Result) then
  begin
    Result := Copy(Result, Length('SysUtils.') + 1, MaxInt);
  end;
end;

/// <summary>Zahl der Parameter von TProc, TFunc bzw. TPredicate mit AArgCount Typargumenten; -1 bei anderen Typen
/// und unpassender Zahl.</summary>
function RtlParamCount(const AName: string; AArgCount: Integer): Integer;
begin
  Result := -1;
  if SameText(AName, 'TProc') then
  begin
    Result := AArgCount;
  end
  else if SameText(AName, 'TFunc') then
  begin
    Result := AArgCount - 1;
  end
  else if SameText(AName, 'TPredicate') and (AArgCount = 1) then
  begin
    Result := 1;
  end;
  if Result > TRtlMethodReferences.cMaxParams then
  begin
    Result := -1;
  end;
end;

/// <summary>Namen der Typparameter für die Parameter: T bei einem, sonst T1, T2 …</summary>
function ParamTypeNames(ACount: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if ACount = 1 then
  begin
    Result := TArray<string>.Create('T');
    Exit;
  end;
  for mIndex := 1 to ACount do
  begin
    Result := Result + [Format('T%d', [mIndex])];
  end;
end;

/// <summary>Parameterliste "(Arg1: T1; Arg2: T2)" zu den Typparametern ATypeNames; '' ohne.</summary>
function ParamList(const ATypeNames: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ATypeNames) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + '; ';
    end;
    Result := Result + Format('Arg%d: %s', [mIndex + 1, ATypeNames[mIndex]]);
  end;
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

/// <summary>Typparameter des Typs AName mit ACount Parametern in der Reihenfolge der Deklaration.</summary>
function TypeParams(const AName: string; ACount: Integer): TArray<string>;
begin
  Result := ParamTypeNames(ACount);
  if SameText(AName, 'TFunc') then
  begin
    Result := Result + ['TResult'];
  end;
end;

class function TRtlMethodReferences.Declaration(const ABase: string; AArgCount: Integer): string;
var
  mName, mGeneric: string;
  mCount: Integer;
  mParams: TArray<string>;
begin
  Result := '';
  mName := RtlName(ABase);
  mCount := RtlParamCount(mName, AArgCount);
  if mCount < 0 then
  begin
    Exit;
  end;
  mParams := ParamTypeNames(mCount);
  mGeneric := string.Join(', ', TypeParams(mName, mCount));
  if mGeneric <> '' then
  begin
    mGeneric := '<' + mGeneric + '>';
  end;
  if SameText(mName, 'TProc') then
  begin
    Result := 'TProc' + mGeneric + ' = reference to procedure' + ParamList(mParams) + ';';
  end
  else if SameText(mName, 'TPredicate') then
  begin
    Result := 'TPredicate<T> = reference to function(Arg1: T): Boolean;';
  end
  else
  begin
    Result := 'TFunc' + mGeneric + ' = reference to function' + ParamList(mParams) + ': TResult;';
  end;
end;

class function TRtlMethodReferences.Find(const ATypeText: string; out AReference: TRtlMethodReference): Boolean;
var
  mBase: string;
  mArgs, mParams: TArray<string>;
  mIndex: Integer;
begin
  AReference := Default(TRtlMethodReference);
  mArgs := TypeArgs(ATypeText, mBase);
  AReference.Signature := Declaration(mBase, Length(mArgs));
  Result := AReference.Signature <> '';
  if not Result then
  begin
    Exit;
  end;
  AReference.Name := RtlName(mBase);
  mParams := TypeParams(AReference.Name, RtlParamCount(AReference.Name, Length(mArgs)));
  for mIndex := 0 to High(mArgs) do
  begin
    AReference.Bindings := AReference.Bindings + [mParams[mIndex] + '=' + mArgs[mIndex]];
  end;
end;

class function TRtlMethodReferences.IsSysUtils(const AUnitName: string): Boolean;
begin
  Result := SameText(AUnitName, 'System.SysUtils') or SameText(AUnitName, 'SysUtils');
end;

end.
