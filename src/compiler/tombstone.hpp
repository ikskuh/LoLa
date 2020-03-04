#ifndef TOMBSTONE_HPP
#define TOMBSTONE_HPP

#include <memory>
#include <mutex>
#include <optional>

namespace LoLa::Runtime {
    struct Function;
}

namespace LoLa
{
    struct Object;

    struct Tombstone
    {
        std::mutex mutex;
        Object * object;

        Tombstone(Object * obj) : mutex(), object(obj) { }
    };

    struct ObjectLock
    {
        std::shared_ptr<Tombstone> ref;
        std::lock_guard<std::mutex> lock;

        explicit ObjectLock(std::shared_ptr<Tombstone> stone) :
            ref(stone),
            lock(stone->mutex)
        {

        }

        Object * operator ->() {
            return ref->object;
        }

        Object * operator &() {
            return ref->object;
        }

        Object & operator *() {
            return *ref->object;
        }

        operator Object &() {
            return *ref->object;
        }

        operator bool() const {
            return (ref->object != nullptr);
        }
    };

    struct Object
    {
        std::shared_ptr<Tombstone> tombstone;

        Object() : tombstone(std::make_shared<Tombstone>(this)) { }
        Object(Object const &) : tombstone(std::make_shared<Tombstone>(this)) { }
        Object(Object && other) :
            tombstone(std::move(other.tombstone))
        {
            tombstone->object = this;
        }
        virtual ~Object() { }

        virtual std::optional<Runtime::Function const *> getFunction(std::string const & name) const = 0;
    };

    struct ObjectRef
    {
        std::shared_ptr<Tombstone> ref;

        ObjectRef(Object & obj) : ref(obj.tombstone) { }
        ObjectRef(Object * obj) : ref(obj->tombstone) { }

        ObjectLock lock() const {
            return ObjectLock { ref };
        }

        bool operator==(ObjectRef const & other) const {
            return ref == other.ref;
        }

        bool operator!=(ObjectRef const & other) const {
            return ref != other.ref;
        }
    };
}

#endif // TOMBSTONE_HPP
