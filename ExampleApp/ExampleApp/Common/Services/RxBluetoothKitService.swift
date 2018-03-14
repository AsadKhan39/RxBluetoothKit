import Foundation
import RxBluetoothKit
import RxSwift
import RxCocoa

// RxBluetoothKitService is a class encapsulating logic of most operations you might want to perform
// on a CentralManager object. Here you can see an example usage of such features as scanning for peripherals,
// discovering services and peripherals.

final class RxBluetoothKitService {

    typealias Disconnection = (Peripheral, DisconnectionReason?)

    // MARK: - Public outputs

    var scanningOutput: Observable<ScannedPeripheral> {
        return scanningSubject.share(replay: 1, scope: .forever).asObservable()
    }

    var servicesOutput: Observable<[Service]> {
        return servicesSubject.asObservable()
    }

    var disconnectionReasonOutput: Observable<Disconnection> {
        return disconnectionSubject.asObservable()
    }

    var errorOutput: Observable<Error> {
        return errorSubject.asObservable()
    }

    // MARK: - Private subjects

    private let scanningSubject = PublishSubject<ScannedPeripheral>()

    private let servicesSubject = PublishSubject<[Service]>()

    private let disconnectionSubject = PublishSubject<Disconnection>()

    private let errorSubject = PublishSubject<Error>()

    // MARK: - Private fields

    private let centralManager = CentralManager(queue: .main)

    private let scheduler: ConcurrentDispatchQueueScheduler

    private let disposeBag = DisposeBag()

    private var connectedPeripherals: [Peripheral] = []

    private var scanningDisposable: Disposable!

    // MARK: - Initialization
    init() {
        let timerQueue = DispatchQueue(label: Constant.Strings.defaultDispatchQueueLabel)
        scheduler = ConcurrentDispatchQueueScheduler(queue: timerQueue)
    }


    // MARK: - Scanning for peripherals

    // You start from observing state of your CentralManager object. Within RxBluetoothKit v.5.0, it is crucial
    // that you use .startWith(:_) operator, and pass the initial state of your CentralManager with
    // centralManager.state.
    func startScanning() {
        scanningDisposable = centralManager.observeState()
                .startWith(centralManager.state)
                .filter {
                    $0 == .poweredOn
                }
                .subscribeOn(MainScheduler.instance)
                .timeout(4.0, scheduler: scheduler)
                .flatMap { [unowned self] _ -> Observable<ScannedPeripheral> in
                    return self.centralManager.scanForPeripherals(withServices: nil)
                }.bind(to: scanningSubject)
    }
    // If you wish to stop scanning for peripherals, you need to dispose the Disposable object, that is created when
    // you either subscribe for events from an observable returned by centralManager.scanForPeripherals(:_), or you bind
    // an observer to it. Check starScanning() above for details.
    func stopScanning() {
        scanningDisposable.dispose()
    }


    // MARK: - Discovering Services

    // When you discover a service, first you need to establish a connection with a peripheral. Then you call
    // discoverServices(:_) that peripheral object.
    func discoverServices(for peripheral: Peripheral) {
        centralManager.establishConnection(peripheral)
                .do(onNext: { [unowned self] _ in
                    self.addConnected(peripheral)
                    self.observeDisconnect(for: peripheral)
                })
                .flatMap {
                    $0.discoverServices(nil)
                }.bind(to: servicesSubject)
                .disposed(by: disposeBag)
    }


    // MARK: - Discovering Characteristics
    func discoverCharacteristics(for service: Service) -> Observable<[Characteristic]> {
        return service.discoverCharacteristics(nil).asObservable()
    }

    // MARK: - Utility functions

    // You might be connected with more than one peripheral at a time, so it's a good decision to keep a collection
    // of currently connected peripherals.
    private func addConnected(_ peripheral: Peripheral) {
        let peripherals = connectedPeripherals.filter {
            $0 == peripheral
        }
        if peripherals.isEmpty {
            connectedPeripherals.append(peripheral)
        }
    }

    // When you observe disconnection from a peripheral, you want to be sure that you take an action on both .next and
    // .error events. For instance, when your device enters BluetoothState.poweredOff, you will receive an .error event.
    private func observeDisconnect(for peripheral: Peripheral) {
        centralManager.observeDisconnect(for: peripheral).subscribe(onNext: { [unowned self] (peripheral, reason) in
            self.disconnectionSubject.onNext((peripheral, reason))
            self.removeDisconnected(peripheral)
        }, onError: { [unowned self] error in
            self.errorSubject.onNext(error)
        }).disposed(by: disposeBag)
    }

    // Removal of disconnected Peripheral from the Peripheral's collection.
    private func removeDisconnected(_ peripheral: Peripheral) {
        connectedPeripherals = connectedPeripherals.filter() {
            $0 !== peripheral
        }
    }
}
