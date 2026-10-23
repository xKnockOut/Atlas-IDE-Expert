{$mode delphi}{$H+}{$modeswitch unicodestrings}{$modeswitch advancedrecords}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}
unit DelphiCompat;

// Typen der Delphi-RTL, die Free Pascal (trunk) nicht oder anders mitbringt
// (#1109). Convert-ForFpc.py trägt die Unit in jede umgewandelte Unit ein.
// TMonitor kommt aus der RTL von FPC; die Unit fpmonitor im Programm stellt die
// Umsetzung bereit.

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TProc = reference to procedure;
  TProc<T> = reference to procedure(Arg1: T);
  TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);
  TProc<T1, T2, T3> = reference to procedure(Arg1: T1; Arg2: T2; Arg3: T3);
  TProc<T1, T2, T3, T4> = reference to procedure(Arg1: T1; Arg2: T2; Arg3: T3; Arg4: T4);
  TFunc<TResult> = reference to function: TResult;
  TFunc<T, TResult> = reference to function(Arg1: T): TResult;
  TFunc<T1, T2, TResult> = reference to function(Arg1: T1; Arg2: T2): TResult;
  TFunc<T1, T2, T3, TResult> = reference to function(Arg1: T1; Arg2: T2; Arg3: T3): TResult;
  TFunc<T1, T2, T3, T4, TResult> = reference to function(Arg1: T1; Arg2: T2; Arg3: T3; Arg4: T4): TResult;
  TPredicate<T> = reference to function(Arg1: T): Boolean;

  /// <summary>In Delphi Basis von EFCreateError und EFOpenError; in FPC leiten beide direkt von EStreamError ab.
  /// Der Alias fängt deshalb etwas mehr (auch EReadError, EWriteError).</summary>
  EFileStreamError = EStreamError;

  /// <summary>Wie System.SyncObjs.TLightweightEvent in Delphi: ein manuell zurückgesetztes Ereignis.</summary>
  TLightweightEvent = class(TEvent)
  public
    constructor Create; overload;
    constructor Create(AInitialState: Boolean); overload;
  end;

  /// <summary>Delphis TUTF8Encoding.Create(False): UTF-8 ohne Präambel. FPC kennt den Parameter nicht;
  /// Convert-ForFpc.py ersetzt den Aufruf durch diese Klasse.</summary>
  TUTF8NoBomEncoding = class(TUTF8Encoding)
  public
    function GetPreamble: TBytes; override;
  end;

implementation

function TUTF8NoBomEncoding.GetPreamble: TBytes;
begin
  Result := nil;
end;

constructor TLightweightEvent.Create;
begin
  inherited Create(nil, True, False, '');
end;

constructor TLightweightEvent.Create(AInitialState: Boolean);
begin
  inherited Create(nil, True, AInitialState, '');
end;

initialization
  // Delphi rechnet string intern in UTF-16; Umwandlungen nach AnsiString (Format mit Literal, Dateinamen)
  // sollen unabhängig von der Locale des Containers (oft "C", also ASCII) verlustfrei bleiben.
  DefaultSystemCodePage := CP_UTF8;
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;

end.
