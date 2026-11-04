#include <mln/storage/http_file_source.hpp>
#include <mln/storage/resource_options.hpp>
#include <mln/util/async_request.hpp>
#include <mln/util/client_options.hpp>

#include <stdexcept>

namespace mln {

// Offline executable tests never create a JVM or request remote resources.
class HTTPFileSource::Impl {
public:
    Impl(const ResourceOptions& resources_, const ClientOptions& client_)
        : resources(resources_.clone()), client(client_.clone()) {}

    ResourceOptions resources;
    ClientOptions client;
};

HTTPFileSource::HTTPFileSource(const ResourceOptions& resources, const ClientOptions& client)
    : impl(std::make_unique<Impl>(resources, client)) {}

HTTPFileSource::~HTTPFileSource() = default;

std::unique_ptr<AsyncRequest> HTTPFileSource::request(const Resource&, Callback) {
    throw std::logic_error("Offline native regression requested a network resource");
}

void HTTPFileSource::setResourceOptions(ResourceOptions options) {
    impl->resources = options.clone();
}

ResourceOptions HTTPFileSource::getResourceOptions() {
    return impl->resources.clone();
}

void HTTPFileSource::setClientOptions(ClientOptions options) {
    impl->client = options.clone();
}

ClientOptions HTTPFileSource::getClientOptions() {
    return impl->client.clone();
}

} // namespace mln
