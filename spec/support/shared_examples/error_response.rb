RSpec.shared_examples "an error response" do |expected_status|
  it "includes all RFC 7807 fields plus suggestion and docs" do
    body = JSON.parse(response.body)
    expect(body["type"]).to be_a(String)
    expect(body["title"]).to be_a(String)
    expect(body["status"]).to eq(expected_status)
    expect(body["detail"]).to be_a(String)
    expect(body["suggestion"]).to be_a(String)
    expect(body["docs"]).to match(%r{https://docs\.konexzero\.com/errors/})
  end
end
