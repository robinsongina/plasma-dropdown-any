/****************************************************************************
** Meta object code from reading C++ file 'kcm_dropdown_any.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.11.1)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../kcm_dropdown_any.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'kcm_dropdown_any.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.11.1. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN14DropdownAnyKCME_t {};
} // unnamed namespace

template <> constexpr inline auto DropdownAnyKCM::qt_create_metaobjectdata<qt_meta_tag_ZN14DropdownAnyKCME_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "DropdownAnyKCM",
        "activeWindowsChanged",
        "",
        "slotsChanged",
        "setSlot",
        "idx",
        "windowClass",
        "shortcut",
        "widthPct",
        "heightPct",
        "activeWindows",
        "slots",
        "QVariantList"
    };

    QtMocHelpers::UintData qt_methods {
        // Signal 'activeWindowsChanged'
        QtMocHelpers::SignalData<void()>(1, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'slotsChanged'
        QtMocHelpers::SignalData<void()>(3, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'setSlot'
        QtMocHelpers::MethodData<void(int, const QString &, const QString &, int, int)>(4, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::Int, 5 }, { QMetaType::QString, 6 }, { QMetaType::QString, 7 }, { QMetaType::Int, 8 },
            { QMetaType::Int, 9 },
        }}),
    };
    QtMocHelpers::UintData qt_properties {
        // property 'activeWindows'
        QtMocHelpers::PropertyData<QStringList>(10, QMetaType::QStringList, QMC::DefaultPropertyFlags, 0),
        // property 'slots'
        QtMocHelpers::PropertyData<QVariantList>(11, 0x80000000 | 12, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
    };
    QtMocHelpers::UintData qt_enums {
    };
    return QtMocHelpers::metaObjectData<DropdownAnyKCM, qt_meta_tag_ZN14DropdownAnyKCME_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums);
}
Q_CONSTINIT const QMetaObject DropdownAnyKCM::staticMetaObject = { {
    QMetaObject::SuperData::link<KQuickConfigModule::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14DropdownAnyKCME_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14DropdownAnyKCME_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN14DropdownAnyKCME_t>.metaTypes,
    nullptr
} };

void DropdownAnyKCM::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<DropdownAnyKCM *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->activeWindowsChanged(); break;
        case 1: _t->slotsChanged(); break;
        case 2: _t->setSlot((*reinterpret_cast<std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[3])),(*reinterpret_cast<std::add_pointer_t<int>>(_a[4])),(*reinterpret_cast<std::add_pointer_t<int>>(_a[5]))); break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        if (QtMocHelpers::indexOfMethod<void (DropdownAnyKCM::*)()>(_a, &DropdownAnyKCM::activeWindowsChanged, 0))
            return;
        if (QtMocHelpers::indexOfMethod<void (DropdownAnyKCM::*)()>(_a, &DropdownAnyKCM::slotsChanged, 1))
            return;
    }
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QStringList*>(_v) = _t->activeWindows(); break;
        case 1: *reinterpret_cast<QVariantList*>(_v) = _t->slots(); break;
        default: break;
        }
    }
}

const QMetaObject *DropdownAnyKCM::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *DropdownAnyKCM::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14DropdownAnyKCME_t>.strings))
        return static_cast<void*>(this);
    return KQuickConfigModule::qt_metacast(_clname);
}

int DropdownAnyKCM::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = KQuickConfigModule::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 3)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 3;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 3)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 3;
    }
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 2;
    }
    return _id;
}

// SIGNAL 0
void DropdownAnyKCM::activeWindowsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void DropdownAnyKCM::slotsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}
QT_WARNING_POP
