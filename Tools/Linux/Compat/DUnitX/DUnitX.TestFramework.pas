{$mode delphi}{$H+}{$modeswitch unicodestrings}{$modeswitch advancedrecords}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}
unit DUnitX.TestFramework;

// Schlanker Ersatz für DUnitX im FPC-Testlauf (Tools/Linux/Test-Fpc.sh). DUnitX selbst lässt sich mit
// FPC nicht übersetzen, weil es auf erweiterter RTTI und Attributen aufbaut. Convert-ForFpc.py entfernt
// mit --tests die Attribute; New-FpcTestProgram.py ruft die Testmethoden direkt auf. Hier stehen nur
// Assert und die Ausnahmen, die die Testunits von Atlas benutzen. Ein fehlgeschlagenes Assert wirft
// ETestFailure, Assert.Pass wirft ETestPass; beides wertet das erzeugte Programm aus.
interface
uses SysUtils, Classes, StrUtils, DelphiCompat;
procedure Fails(const AWhat, AMessage: string);
type
  ETestFailure = class(Exception);
  ETestPass = class(Exception);
  TTestLocalMethod = reference to procedure;
  ExceptClass = class of Exception;
  Assert = class
  public
    class procedure Fail(const AMessage: string = ''); static;
    class procedure Pass(const AMessage: string = ''); static;
    class procedure IsTrue(ACondition: Boolean; const AMessage: string = ''); static;
    class procedure IsFalse(ACondition: Boolean; const AMessage: string = ''); static;
    class procedure IsNull(AObject: TObject; const AMessage: string = ''); overload; static;
    class procedure IsNull(APointer: Pointer; const AMessage: string = ''); overload; static;
    class procedure IsNull(const AIntf: IInterface; const AMessage: string = ''); overload; static;
    class procedure IsNotNull(AObject: TObject; const AMessage: string = ''); overload; static;
    class procedure IsNotNull(APointer: Pointer; const AMessage: string = ''); overload; static;
    class procedure IsNotNull(const AIntf: IInterface; const AMessage: string = ''); overload; static;
    class procedure AreEqual(const AExpected, AActual: string; const AMessage: string = ''); overload; static;
    class procedure AreEqual(const AExpected, AActual: string; AIgnoreCase: Boolean; const AMessage: string = ''); overload; static;
    class procedure AreEqual(AExpected, AActual: Int64; const AMessage: string = ''); overload; static;
    class procedure AreEqual(AExpected, AActual: Integer; const AMessage: string = ''); overload; static;
    class procedure AreEqual(AExpected, AActual: Cardinal; const AMessage: string = ''); overload; static;
    class procedure AreEqual(AExpected, AActual: Boolean; const AMessage: string = ''); overload; static;
    class procedure AreEqual(const AExpected, AActual, ATolerance: Double; const AMessage: string = ''); overload; static;
    class procedure AreEqual(const AExpected, AActual: Double; const AMessage: string = ''); overload; static;
    class procedure AreEqual(AExpected, AActual: TObject; const AMessage: string = ''); overload; static;
    class procedure AreEqual<T>(const AExpected, AActual: T; const AMessage: string = ''); overload; static;
    class procedure AreNotEqual(const AExpected, AActual: string; const AMessage: string = ''); overload; static;
    class procedure AreNotEqual(AExpected, AActual: Int64; const AMessage: string = ''); overload; static;
    class procedure AreNotEqual(AExpected, AActual: Integer; const AMessage: string = ''); overload; static;
    class procedure AreNotEqual<T>(const AExpected, AActual: T; const AMessage: string = ''); overload; static;
    class procedure AreSame(AExpected, AActual: TObject; const AMessage: string = ''); overload; static;
    class procedure AreSame(const AExpected, AActual: IInterface; const AMessage: string = ''); overload; static;
    class procedure Contains(const AText, ASub: string; const AMessage: string = ''); overload; static;
    class procedure Contains(const AText, ASub: string; AIgnoreCase: Boolean; const AMessage: string = ''); overload; static;
    class procedure Contains<T>(const AArray: TArray<T>; const AValue: T; const AMessage: string = ''); overload; static;
    class procedure DoesNotContain(const AText, ASub: string; const AMessage: string = ''); overload; static;
    class procedure DoesNotContain(const AText, ASub: string; AIgnoreCase: Boolean; const AMessage: string = ''); overload; static;
    class procedure StartsWith(const APrefix, AText: string; const AMessage: string = ''); overload; static;
    class procedure StartsWith(const APrefix, AText: string; AIgnoreCase: Boolean; const AMessage: string = ''); overload; static;
    class procedure EndsWith(const ASuffix, AText: string; const AMessage: string = ''); overload; static;
    class procedure EndsWith(const ASuffix, AText: string; AIgnoreCase: Boolean; const AMessage: string = ''); overload; static;
    class procedure IsNotEmpty(const AText: string; const AMessage: string = ''); overload; static;
    class procedure IsEmpty(const AText: string; const AMessage: string = ''); overload; static;
    class procedure WillRaise(const AMethod: TTestLocalMethod; AClass: ExceptClass = nil; const AMessage: string = ''); static;
    class procedure WillRaiseDescendant(const AMethod: TTestLocalMethod; AClass: ExceptClass = nil; const AMessage: string = ''); static;
    class procedure WillRaiseWithMessage(const AMethod: TTestLocalMethod; AClass: ExceptClass; const AText: string; const AMessage: string = ''); static;
    class procedure WillNotRaise(const AMethod: TTestLocalMethod; AClass: ExceptClass = nil; const AMessage: string = ''); static;
  end;
  TDUnitX = class
    class procedure RegisterTestFixture(AClass: TClass; const AName: string = ''); static;
  end;
implementation
procedure Fails(const AWhat, AMessage: string);
begin
  raise ETestFailure.Create(AWhat + ' ' + AMessage);
end;
class procedure Assert.Fail(const AMessage: string); begin Fails('Fail', AMessage); end;
class procedure Assert.Pass(const AMessage: string); begin raise ETestPass.Create(AMessage); end;
class procedure Assert.IsTrue(ACondition: Boolean; const AMessage: string); begin if not ACondition then Fails('IsTrue', AMessage); end;
class procedure Assert.IsFalse(ACondition: Boolean; const AMessage: string); begin if ACondition then Fails('IsFalse', AMessage); end;
class procedure Assert.IsNull(AObject: TObject; const AMessage: string); begin if AObject <> nil then Fails('IsNull', AMessage); end;
class procedure Assert.IsNull(APointer: Pointer; const AMessage: string); begin if APointer <> nil then Fails('IsNull', AMessage); end;
class procedure Assert.IsNull(const AIntf: IInterface; const AMessage: string); begin if AIntf <> nil then Fails('IsNull', AMessage); end;
class procedure Assert.IsNotNull(AObject: TObject; const AMessage: string); begin if AObject = nil then Fails('IsNotNull', AMessage); end;
class procedure Assert.IsNotNull(APointer: Pointer; const AMessage: string); begin if APointer = nil then Fails('IsNotNull', AMessage); end;
class procedure Assert.IsNotNull(const AIntf: IInterface; const AMessage: string); begin if AIntf = nil then Fails('IsNotNull', AMessage); end;
class procedure Assert.AreEqual(const AExpected, AActual: string; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual erwartet <' + AExpected + '> erhalten <' + AActual + '>', AMessage); end;
class procedure Assert.AreEqual(const AExpected, AActual: string; AIgnoreCase: Boolean; const AMessage: string);
begin if AIgnoreCase then begin if not SameText(AExpected, AActual) then Fails('AreEqual erwartet <' + AExpected + '> erhalten <' + AActual + '>', AMessage) end else AreEqual(AExpected, AActual, AMessage); end;
class procedure Assert.AreEqual(AExpected, AActual: Int64; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual erwartet ' + IntToStr(AExpected) + ' erhalten ' + IntToStr(AActual), AMessage); end;
class procedure Assert.AreEqual(AExpected, AActual: Integer; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual erwartet ' + IntToStr(AExpected) + ' erhalten ' + IntToStr(AActual), AMessage); end;
class procedure Assert.AreEqual(AExpected, AActual: Cardinal; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual erwartet ' + IntToStr(AExpected) + ' erhalten ' + IntToStr(AActual), AMessage); end;
class procedure Assert.AreEqual(AExpected, AActual: Boolean; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual erwartet ' + BoolToStr(AExpected, True) + ' erhalten ' + BoolToStr(AActual, True), AMessage); end;
class procedure Assert.AreEqual(const AExpected, AActual, ATolerance: Double; const AMessage: string);
begin if Abs(AExpected - AActual) > ATolerance then Fails('AreEqual erwartet ' + FloatToStr(AExpected) + ' erhalten ' + FloatToStr(AActual), AMessage); end;
class procedure Assert.AreEqual(const AExpected, AActual: Double; const AMessage: string);
begin AreEqual(AExpected, AActual, 1e-9, AMessage); end;
class procedure Assert.AreEqual(AExpected, AActual: TObject; const AMessage: string);
begin if AExpected <> AActual then Fails('AreEqual Objekt', AMessage); end;
class procedure Assert.AreEqual<T>(const AExpected, AActual: T; const AMessage: string);
begin if not CompareMem(@AExpected, @AActual, SizeOf(T)) then Fails('AreEqual<T>', AMessage); end;
class procedure Assert.AreNotEqual(const AExpected, AActual: string; const AMessage: string); begin if AExpected = AActual then Fails('AreNotEqual <' + AActual + '>', AMessage); end;
class procedure Assert.AreNotEqual(AExpected, AActual: Int64; const AMessage: string); begin if AExpected = AActual then Fails('AreNotEqual ' + IntToStr(AActual), AMessage); end;
class procedure Assert.AreNotEqual(AExpected, AActual: Integer; const AMessage: string); begin if AExpected = AActual then Fails('AreNotEqual ' + IntToStr(AActual), AMessage); end;
class procedure Assert.AreNotEqual<T>(const AExpected, AActual: T; const AMessage: string);
begin if CompareMem(@AExpected, @AActual, SizeOf(T)) then Fails('AreNotEqual<T>', AMessage); end;
class procedure Assert.AreSame(AExpected, AActual: TObject; const AMessage: string); begin if AExpected <> AActual then Fails('AreSame', AMessage); end;
class procedure Assert.AreSame(const AExpected, AActual: IInterface; const AMessage: string); begin if AExpected <> AActual then Fails('AreSame', AMessage); end;
class procedure Assert.Contains(const AText, ASub: string; const AMessage: string); begin Contains(AText, ASub, True, AMessage); end;
class procedure Assert.Contains(const AText, ASub: string; AIgnoreCase: Boolean; const AMessage: string);
begin
  if AIgnoreCase then begin if Pos(LowerCase(ASub), LowerCase(AText)) = 0 then Fails('Contains <' + ASub + '> in <' + AText + '>', AMessage) end
  else if Pos(ASub, AText) = 0 then Fails('Contains <' + ASub + '> in <' + AText + '>', AMessage);
end;
class procedure Assert.Contains<T>(const AArray: TArray<T>; const AValue: T; const AMessage: string);
var I: Integer;
begin
  for I := 0 to High(AArray) do
    if CompareMem(@AArray[I], @AValue, SizeOf(T)) then Exit;
  Fails('Contains<T>', AMessage);
end;
class procedure Assert.DoesNotContain(const AText, ASub: string; const AMessage: string); begin DoesNotContain(AText, ASub, True, AMessage); end;
class procedure Assert.DoesNotContain(const AText, ASub: string; AIgnoreCase: Boolean; const AMessage: string);
begin
  if AIgnoreCase then begin if Pos(LowerCase(ASub), LowerCase(AText)) > 0 then Fails('DoesNotContain <' + ASub + '> in <' + AText + '>', AMessage) end
  else if Pos(ASub, AText) > 0 then Fails('DoesNotContain <' + ASub + '> in <' + AText + '>', AMessage);
end;
class procedure Assert.StartsWith(const APrefix, AText: string; const AMessage: string); begin StartsWith(APrefix, AText, True, AMessage); end;
class procedure Assert.StartsWith(const APrefix, AText: string; AIgnoreCase: Boolean; const AMessage: string);
begin if not (AIgnoreCase and StartsText(APrefix, AText)) and not (not AIgnoreCase and StartsStr(APrefix, AText)) then Fails('StartsWith <' + APrefix + '> <' + AText + '>', AMessage); end;
class procedure Assert.EndsWith(const ASuffix, AText: string; const AMessage: string); begin EndsWith(ASuffix, AText, True, AMessage); end;
class procedure Assert.EndsWith(const ASuffix, AText: string; AIgnoreCase: Boolean; const AMessage: string);
begin if not (AIgnoreCase and EndsText(ASuffix, AText)) and not (not AIgnoreCase and EndsStr(ASuffix, AText)) then Fails('EndsWith <' + ASuffix + '> <' + AText + '>', AMessage); end;
class procedure Assert.IsNotEmpty(const AText: string; const AMessage: string); begin if AText = '' then Fails('IsNotEmpty', AMessage); end;
class procedure Assert.IsEmpty(const AText: string; const AMessage: string); begin if AText <> '' then Fails('IsEmpty <' + AText + '>', AMessage); end;
class procedure Assert.WillRaise(const AMethod: TTestLocalMethod; AClass: ExceptClass; const AMessage: string);
begin
  try
    AMethod();
  except
    on E: Exception do
    begin
      if (AClass <> nil) and (E.ClassType <> AClass) then
        Fails('WillRaise falsche Klasse ' + E.ClassName, AMessage);
      Exit;
    end;
  end;
  Fails('WillRaise ohne Ausnahme', AMessage);
end;
class procedure Assert.WillRaiseDescendant(const AMethod: TTestLocalMethod; AClass: ExceptClass; const AMessage: string);
begin
  try
    AMethod();
  except
    on E: Exception do
    begin
      if (AClass <> nil) and not E.InheritsFrom(AClass) then
        Fails('WillRaiseDescendant falsche Klasse ' + E.ClassName, AMessage);
      Exit;
    end;
  end;
  Fails('WillRaiseDescendant ohne Ausnahme', AMessage);
end;
class procedure Assert.WillRaiseWithMessage(const AMethod: TTestLocalMethod; AClass: ExceptClass; const AText: string; const AMessage: string);
begin
  try
    AMethod();
  except
    on E: Exception do
    begin
      if (AText <> '') and (E.Message <> AText) then Fails('WillRaiseWithMessage <' + E.Message + '>', AMessage);
      Exit;
    end;
  end;
  Fails('WillRaiseWithMessage ohne Ausnahme', AMessage);
end;
class procedure Assert.WillNotRaise(const AMethod: TTestLocalMethod; AClass: ExceptClass; const AMessage: string);
begin
  try
    AMethod();
  except
    on E: Exception do Fails('WillNotRaise ' + E.ClassName + ': ' + E.Message, AMessage);
  end;
end;
class procedure TDUnitX.RegisterTestFixture(AClass: TClass; const AName: string); begin end;
end.
